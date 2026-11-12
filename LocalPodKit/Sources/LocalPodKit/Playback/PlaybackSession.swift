import Foundation
import SwiftData

/// App-level coordinator that connects the player, persisted queue, playlists,
/// sleep timer and user settings. Views send intents here instead of wiring the
/// pieces themselves.
@MainActor
@Observable
public final class PlaybackSession {
    public let playback: PlaybackController
    public let queue: QueueManager
    public let playlists: PlaylistService
    public let settings: AppSettingsStore
    public let sleepTimer: SleepTimer

    public private(set) var lastError: String?

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private let itemBuilder: @MainActor (MediaItem) -> PlaybackItem?
    /// Security scope for the currently loaded in-place item. Held for as
    /// long as that item is loaded (including background audio) and released
    /// when another item loads or playback stops.
    @ObservationIgnored private var activeLinkedAccess: LinkedFolderStore.ResolvedAccess?

    public init(
        playback: PlaybackController = PlaybackController(),
        settings: AppSettingsStore = AppSettingsStore(),
        sleepTimer: SleepTimer = SleepTimer(),
        itemBuilder: (@MainActor (MediaItem) -> PlaybackItem?)? = nil
    ) {
        self.playback = playback
        self.settings = settings
        self.sleepTimer = sleepTimer
        self.itemBuilder = itemBuilder ?? { PlaybackSession.defaultItemBuilder($0) }
        queue = QueueManager()
        playlists = PlaylistService()

        playback.onItemEnded = { [weak self] in
            self?.handleItemEnded()
        }
        playback.onNextTrack = { [weak self] in
            self?.next(userInitiated: true)
        }
        playback.onPreviousTrack = { [weak self] in
            self?.previous(userInitiated: true)
        }
        sleepTimer.onFire = { [weak self] in
            self?.handleSleepTimerFired()
        }
        sleepTimer.onVolumeChange = { [weak self] value in
            self?.playback.player.volume = value
        }
    }

    /// Call once the SwiftData container exists. Restores the saved queue and
    /// loads its current item paused; it never auto-plays on launch.
    public func attach(
        context: ModelContext,
        progressStore: PlaybackProgressStore? = nil
    ) {
        self.context = context
        if let progressStore {
            playback.attachProgressStore(progressStore)
        }
        queue.attach(context: context)
        playlists.attach(context: context)
        applySettings()
        restoreQueue()
    }

    public func applySettings() {
        playback.setRate(settings.defaultRate)
        playback.setSkipIntervals(
            forward: settings.skipForwardSeconds,
            backward: settings.skipBackwardSeconds
        )
        playback.resumesSavedProgress = settings.resumeEnabled
    }

    /// Changes the playback speed and remembers it. The player's speed chips
    /// call this instead of `playback.setRate` so the choice is written to
    /// AppSettingsStore (the same UserDefaults path as every other setting)
    /// and `attach` re-applies it on the next launch — killing the app used
    /// to bring the speed back to 1× because only the player knew the value.
    public func setRate(_ rate: Float) {
        let clamped = PlaybackPolicy.clampedRate(rate)
        settings.defaultRate = clamped
        playback.setRate(clamped)
    }

    // MARK: - Play intents

    public func play(item: MediaItem) {
        queue.setQueue(itemIDs: [item.id], current: item.id)
        if !loadItem(id: item.id, autoplay: true) {
            lastError = LocalPodLocalization.format(
                "playback.error.missingFileNamed",
                item.title
            )
        }
    }

    /// "Play all" for collections and playlists. Replaces the queue.
    public func play(
        items: [MediaItem],
        startingAt index: Int = 0,
        shuffle: Bool = false
    ) {
        guard !items.isEmpty else { return }
        let safeIndex = min(max(index, 0), items.count - 1)
        queue.setQueue(
            itemIDs: items.map(\.id),
            current: items[safeIndex].id,
            shuffle: shuffle
        )
        if !loadItem(id: items[safeIndex].id, autoplay: true) {
            lastError = LocalPodLocalization.format(
                "playback.error.missingFileNamed",
                items[safeIndex].title
            )
        }
    }

    public func playNext(itemID: UUID) {
        let wasEmpty = queue.currentItemID == nil
        queue.insertNext(itemID)
        if wasEmpty {
            _ = loadItem(id: itemID, autoplay: true)
        }
    }

    public func enqueue(itemID: UUID) {
        let wasEmpty = queue.currentItemID == nil
        queue.append(itemID)
        if wasEmpty {
            _ = loadItem(id: itemID, autoplay: false)
        }
    }

    public func playQueueItem(itemID: UUID) {
        queue.setCurrent(itemID)
        if !loadItem(id: itemID, autoplay: true) {
            lastError = LocalPodLocalization.string("playback.error.missingFile")
        }
    }

    /// Shortcuts/Siri "continue playback". Prefers the persisted queue's
    /// current item; when there is no playable queue item, falls back to the
    /// most recently played unfinished item. Returns false when nothing can be
    /// resumed so the caller can leave the UI untouched.
    @discardableResult
    public func resumeForShortcut() -> Bool {
        if let currentItemID = queue.currentItemID,
           mediaItem(for: currentItemID) != nil {
            queue.setCurrent(currentItemID)
            return loadItem(id: currentItemID, autoplay: true)
        }

        guard let context else { return false }
        var descriptor = FetchDescriptor<PlaybackState>(
            predicate: #Predicate { $0.playCount > 0 && !$0.isFinished },
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let state = try? context.fetch(descriptor).first,
              mediaItem(for: state.itemID) != nil else {
            return false
        }
        queue.setQueue(itemIDs: [state.itemID], current: state.itemID)
        return loadItem(id: state.itemID, autoplay: true)
    }

    public func next(userInitiated: Bool = true) {
        let autoplay = userInitiated ? playback.isPlaying : true
        guard let nextID = queue.advance() else { return }
        _ = loadItem(id: nextID, autoplay: autoplay)
    }

    public func previous(userInitiated: Bool = true) {
        let autoplay = userInitiated ? playback.isPlaying : true
        guard let previousID = queue.previous() else { return }
        _ = loadItem(id: previousID, autoplay: autoplay)
    }

    public func removeQueueEntry(entryID: UUID) {
        let wasCurrent = queue.entries
            .first(where: { $0.id == entryID })?
            .itemID == queue.currentItemID
        let autoplay = playback.isPlaying
        queue.removeEntry(id: entryID)
        guard wasCurrent else { return }
        if let itemID = queue.currentItemID {
            _ = loadItem(id: itemID, autoplay: autoplay)
        } else {
            playback.stop()
        }
    }

    public func clearQueue() {
        queue.clear()
        playback.stop()
        releaseLinkedAccess()
    }

    public func moveQueue(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
    }

    public func toggleShuffle() {
        queue.setShuffle(!queue.shuffleEnabled)
    }

    public func cycleRepeatMode() {
        queue.cycleRepeatMode()
    }

    /// Called after a library item is deleted. Playback advances when the
    /// deleted item was current; otherwise the queue entry is simply removed.
    public func handleDeletedItem(_ itemID: UUID) {
        if queue.currentItemID == itemID {
            let autoplay = playback.isPlaying
            if let replacement = queue.removeCurrentAndAdvance() {
                _ = loadItem(id: replacement, autoplay: autoplay)
            } else {
                playback.stop()
                releaseLinkedAccess()
            }
        } else {
            queue.remove(itemID: itemID)
        }
    }

    // MARK: - Sleep timer

    public func startSleepTimer(minutes: Int) {
        sleepTimer.start(minutes: minutes)
    }

    public func startSleepTimerEndOfEpisode() {
        sleepTimer.startEndOfEpisode()
    }

    public func cancelSleepTimer() {
        sleepTimer.cancel()
    }

    // MARK: - Item lookup

    public func mediaItem(for itemID: UUID) -> MediaItem? {
        guard let context else { return nil }
        var descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.id == itemID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    public func mediaItems(for itemIDs: [UUID]) -> [MediaItem] {
        itemIDs.compactMap { mediaItem(for: $0) }
    }

    // MARK: - Internal behavior

    private func restoreQueue() {
        guard let currentItemID = queue.currentItemID else { return }
        if loadItem(id: currentItemID, autoplay: false) {
            return
        }
        // The current item is gone (for example the media was removed outside
        // the app). Fall forward until a playable item or an empty queue.
        var attempts = queue.count
        while attempts > 0 {
            attempts -= 1
            guard let replacement = queue.removeCurrentAndAdvance() else {
                playback.stop()
                return
            }
            if loadItem(id: replacement, autoplay: false) {
                return
            }
        }
        playback.stop()
    }

    @discardableResult
    private func loadItem(id: UUID, autoplay: Bool) -> Bool {
        guard let mediaItem = mediaItem(for: id),
              let playbackItem = playbackItem(for: mediaItem) else {
            return false
        }
        lastError = nil
        playback.load(playbackItem, autoplay: autoplay)
        return true
    }

    /// Builds a playable item, resolving the security scope for in-place
    /// imports. The scope stays active until the next load or stop.
    private func playbackItem(for mediaItem: MediaItem) -> PlaybackItem? {
        guard mediaItem.isLinked else {
            return itemBuilder(mediaItem)
        }
        releaseLinkedAccess()

        if let folderID = mediaItem.linkedFolderID, let context {
            var descriptor = FetchDescriptor<LinkedFolder>(
                predicate: #Predicate { $0.id == folderID }
            )
            descriptor.fetchLimit = 1
            guard let folder = try? context.fetch(descriptor).first else { return nil }
            switch LinkedFolderStore.resolve(folder.bookmarkData) {
            case .failure:
                return nil
            case .success(let access):
                if let refreshed = access.refreshedBookmark {
                    folder.bookmarkData = refreshed
                    folder.isStale = false
                    try? context.save()
                }
                let url = access.url.appendingPathComponent(
                    mediaItem.linkedSourceRelativePath
                )
                guard FileManager.default.fileExists(atPath: url.path) else {
                    access.stop()
                    return nil
                }
                activeLinkedAccess = access
                return makePlaybackItem(mediaItem, url: url)
            }
        }

        if let bookmark = mediaItem.linkedBookmarkData {
            switch LinkedFolderStore.resolve(bookmark) {
            case .failure:
                return nil
            case .success(let access):
                guard FileManager.default.fileExists(atPath: access.url.path) else {
                    access.stop()
                    return nil
                }
                activeLinkedAccess = access
                return makePlaybackItem(mediaItem, url: access.url)
            }
        }
        return nil
    }

    private func makePlaybackItem(_ item: MediaItem, url: URL) -> PlaybackItem {
        PlaybackItem(
            title: item.title,
            subtitle: item.folderName
                ?? LocalPodLocalization.string("playback.librarySubtitle"),
            fileURL: url,
            kind: item.kind,
            durationHint: item.durationSeconds,
            libraryItemID: item.id,
            artworkURL: item.artworkURL
        )
    }

    private func releaseLinkedAccess() {
        activeLinkedAccess?.stop()
        activeLinkedAccess = nil
    }

    /// Internal for tests; wired to the controller's end-of-item callback.
    func handleItemEnded() {
        if sleepTimer.consumeEndOfEpisode() {
            return
        }
        guard settings.autoPlayNext else { return }
        guard let nextID = queue.advance() else { return }
        _ = loadItem(id: nextID, autoplay: true)
    }

    private func handleSleepTimerFired() {
        playback.player.volume = 1
        if playback.isPlaying || playback.phase == .buffering {
            playback.pause()
        }
    }

    public static func defaultItemBuilder(_ item: MediaItem) -> PlaybackItem? {
        guard let url = item.fileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return PlaybackItem(
            title: item.title,
            subtitle: item.folderName
                ?? LocalPodLocalization.string("playback.librarySubtitle"),
            fileURL: url,
            kind: item.kind,
            durationHint: item.durationSeconds,
            libraryItemID: item.id,
            artworkURL: item.artworkURL
        )
    }
}
