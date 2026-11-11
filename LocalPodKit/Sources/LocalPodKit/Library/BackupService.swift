import Foundation
import SwiftData

/// JSON backup of the library's DATA (not media files): items, collections,
/// playlists, playback progress, queue state, and app settings. Media files
/// stay under `Application Support/Media` and are re-linked by re-importing
/// the original files; on restore, items whose media file (by relativePath)
/// is absent are inserted with `isMissing = true` so the existing
/// mark-missing → relink-by-fingerprint flow takes over.
///
/// Deliberately NOT exported (see `BackupService`):
/// - `LinkedFolder`: security-scoped bookmarks are device/provider specific
///   and meaningless on another install; the user re-links the folder.
/// - `TrashItem`: the trash is transient staging, not library data.
/// - `ImportSession`: history bookkeeping without restore value.
public struct BackupDocument: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var appVersion: String
    public var exportedAt: Date
    public var items: [BackupItem]
    public var collections: [BackupCollection]
    public var playlists: [BackupPlaylist]
    public var playbackStates: [BackupPlaybackState]
    public var queue: BackupQueueState?
    public var settings: BackupSettings?

    public init(
        schemaVersion: Int = BackupDocument.currentSchemaVersion,
        appVersion: String = "",
        exportedAt: Date = Date(),
        items: [BackupItem] = [],
        collections: [BackupCollection] = [],
        playlists: [BackupPlaylist] = [],
        playbackStates: [BackupPlaybackState] = [],
        queue: BackupQueueState? = nil,
        settings: BackupSettings? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.items = items
        self.collections = collections
        self.playlists = playlists
        self.playbackStates = playbackStates
        self.queue = queue
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, appVersion, exportedAt
        case items, collections, playlists, playbackStates, queue, settings
    }

    /// Tolerant decoding: unknown top-level fields are ignored by
    /// JSONDecoder, and missing sections default to empty instead of failing,
    /// so an older/partial v1 document still restores what it has.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        items = try container.decodeIfPresent([BackupItem].self, forKey: .items) ?? []
        collections = try container.decodeIfPresent([BackupCollection].self, forKey: .collections) ?? []
        playlists = try container.decodeIfPresent([BackupPlaylist].self, forKey: .playlists) ?? []
        playbackStates = try container.decodeIfPresent([BackupPlaybackState].self, forKey: .playbackStates) ?? []
        queue = try container.decodeIfPresent(BackupQueueState.self, forKey: .queue)
        settings = try container.decodeIfPresent(BackupSettings.self, forKey: .settings)
    }
}

/// Every `MediaItem` field needed to rebuild the row. `isMissing` is stored
/// for fidelity but recomputed on restore from actual file existence.
public struct BackupItem: Codable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var sortTitle: String
    public var originalFileName: String
    public var relativePath: String
    public var relativeFolderPath: String
    public var kindRaw: String
    public var fileExtension: String
    public var byteSize: Int64
    public var durationSeconds: Double?
    public var addedAt: Date
    public var folderName: String?
    public var sourceRaw: String
    public var sourceName: String?
    public var fingerprint: String?
    public var collectionID: UUID?
    public var artworkKey: String?
    public var importSessionID: UUID?
    public var isMissing: Bool
    public var isFavorite: Bool
    public var notes: String?

    public init(
        id: UUID,
        title: String,
        sortTitle: String,
        originalFileName: String,
        relativePath: String,
        relativeFolderPath: String,
        kindRaw: String,
        fileExtension: String,
        byteSize: Int64,
        durationSeconds: Double?,
        addedAt: Date,
        folderName: String?,
        sourceRaw: String,
        sourceName: String?,
        fingerprint: String?,
        collectionID: UUID?,
        artworkKey: String?,
        importSessionID: UUID?,
        isMissing: Bool,
        isFavorite: Bool,
        notes: String?
    ) {
        self.id = id
        self.title = title
        self.sortTitle = sortTitle
        self.originalFileName = originalFileName
        self.relativePath = relativePath
        self.relativeFolderPath = relativeFolderPath
        self.kindRaw = kindRaw
        self.fileExtension = fileExtension
        self.byteSize = byteSize
        self.durationSeconds = durationSeconds
        self.addedAt = addedAt
        self.folderName = folderName
        self.sourceRaw = sourceRaw
        self.sourceName = sourceName
        self.fingerprint = fingerprint
        self.collectionID = collectionID
        self.artworkKey = artworkKey
        self.importSessionID = importSessionID
        self.isMissing = isMissing
        self.isFavorite = isFavorite
        self.notes = notes
    }
}

public struct BackupCollection: Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var sortOrder: Int

    public init(id: UUID, name: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }
}

public struct BackupPlaylistEntry: Codable, Sendable, Equatable {
    public var itemID: UUID
    public var position: Int

    public init(itemID: UUID, position: Int) {
        self.itemID = itemID
        self.position = position
    }
}

public struct BackupPlaylist: Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var sortOrder: Int
    public var entries: [BackupPlaylistEntry]

    public init(id: UUID, name: String, sortOrder: Int, entries: [BackupPlaylistEntry]) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.entries = entries
    }
}

public struct BackupPlaybackState: Codable, Sendable, Equatable {
    public var itemID: UUID
    public var position: Double
    public var duration: Double
    public var isFinished: Bool
    public var playCount: Int
    public var lastPlayedAt: Date?
    public var updatedAt: Date

    public init(
        itemID: UUID,
        position: Double,
        duration: Double,
        isFinished: Bool,
        playCount: Int,
        lastPlayedAt: Date?,
        updatedAt: Date
    ) {
        self.itemID = itemID
        self.position = position
        self.duration = duration
        self.isFinished = isFinished
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
        self.updatedAt = updatedAt
    }
}

public struct BackupQueueEntry: Codable, Sendable, Equatable {
    public var itemID: UUID
    public var position: Int

    public init(itemID: UUID, position: Int) {
        self.itemID = itemID
        self.position = position
    }
}

public struct BackupQueueState: Codable, Sendable, Equatable {
    public var entries: [BackupQueueEntry]
    public var currentItemID: UUID?
    public var shuffleEnabled: Bool
    public var repeatModeRaw: String
    public var shuffleOrder: [UUID]

    public init(
        entries: [BackupQueueEntry],
        currentItemID: UUID?,
        shuffleEnabled: Bool,
        repeatModeRaw: String,
        shuffleOrder: [UUID]
    ) {
        self.entries = entries
        self.currentItemID = currentItemID
        self.shuffleEnabled = shuffleEnabled
        self.repeatModeRaw = repeatModeRaw
        self.shuffleOrder = shuffleOrder
    }
}

/// Mirror of `AppSettingsStore`'s six user-facing fields.
public struct BackupSettings: Codable, Sendable, Equatable {
    public var defaultRate: Float
    public var skipForwardSeconds: Double
    public var skipBackwardSeconds: Double
    public var resumeEnabled: Bool
    public var autoPlayNext: Bool
    public var signingReminderEnabled: Bool

    public init(
        defaultRate: Float,
        skipForwardSeconds: Double,
        skipBackwardSeconds: Double,
        resumeEnabled: Bool,
        autoPlayNext: Bool,
        signingReminderEnabled: Bool
    ) {
        self.defaultRate = defaultRate
        self.skipForwardSeconds = skipForwardSeconds
        self.skipBackwardSeconds = skipBackwardSeconds
        self.resumeEnabled = resumeEnabled
        self.autoPlayNext = autoPlayNext
        self.signingReminderEnabled = signingReminderEnabled
    }

    /// Reads the store's current values. `AppSettingsStore` is MainActor-
    /// isolated, so this (and `apply`) must run on the main actor.
    @MainActor
    public init(store: AppSettingsStore) {
        self.init(
            defaultRate: store.defaultRate,
            skipForwardSeconds: store.skipForwardSeconds,
            skipBackwardSeconds: store.skipBackwardSeconds,
            resumeEnabled: store.resumeEnabled,
            autoPlayNext: store.autoPlayNext,
            signingReminderEnabled: store.signingReminderEnabled
        )
    }

    /// Applies the stored values through the store's setters (which persist
    /// immediately), clamping exactly like `AppSettingsStore` does on read.
    @MainActor
    public func apply(to store: AppSettingsStore) {
        store.defaultRate = PlaybackPolicy.clampedRate(defaultRate)
        store.skipForwardSeconds = Self.clampedSkip(skipForwardSeconds)
        store.skipBackwardSeconds = Self.clampedSkip(skipBackwardSeconds)
        store.resumeEnabled = resumeEnabled
        store.autoPlayNext = autoPlayNext
        store.signingReminderEnabled = signingReminderEnabled
    }

    private static func clampedSkip(_ value: Double) -> Double {
        guard value.isFinite else { return 15 }
        return min(max(value, 5), 120)
    }
}

/// What a restore changed. Matching rules are documented on
/// `BackupService.restore(_:into:settings:)`.
public struct BackupRestoreResult: Sendable, Equatable {
    /// Backup items that matched an existing row (by id or fingerprint) and
    /// were therefore not inserted again.
    public var itemsMatched: Int = 0
    /// New `MediaItem` rows created from the backup.
    public var itemsRestored: Int = 0
    /// Restored rows whose media file does not exist (`isMissing = true`).
    public var itemsMissingMedia: Int = 0
    /// New `MediaCollection` rows created.
    public var collectionsRestored: Int = 0
    /// Existing playlists a backup playlist merged into (same name).
    public var playlistsMerged: Int = 0
    /// Playlists created because no playlist had that name.
    public var playlistsCreated: Int = 0
    /// Playlist entries actually added (new membership only).
    public var playlistEntriesAdded: Int = 0
    /// Playback-state rows written: brand-new states plus existing states
    /// overwritten because the backup's `updatedAt` was newer.
    public var progressUpdated: Int = 0
    /// Dependent rows (playlist entries, playback states, queue entries)
    /// dropped because their item id resolved to nothing in the backup items
    /// or the current library.
    public var skipped: Int = 0

    public init() {}
}

public enum BackupError: LocalizedError, Equatable, Sendable {
    case corruptJSON
    case unsupportedVersion(found: Int)
    case readFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .corruptJSON:
            LocalPodLocalization.string("backup.error.corrupt")
        case .unsupportedVersion(let found):
            LocalPodLocalization.format(
                "backup.error.version",
                found,
                BackupDocument.currentSchemaVersion
            )
        case .readFailed(let detail):
            LocalPodLocalization.format("backup.error.readFailed", detail)
        case .writeFailed(let detail):
            LocalPodLocalization.format("backup.error.writeFailed", detail)
        }
    }
}

/// Snapshot and restore of the data-only backup document. All SwiftData work
/// happens on the MainActor, matching `LibraryService` / `TrashService`.
@MainActor
public final class BackupService {
    public let storage: MediaStorage

    public init(storage: MediaStorage = .live) {
        self.storage = storage
    }

    // MARK: - Snapshot

    /// Reads the current library into a backup document. Benchmark rows are
    /// excluded (they are performance fixtures, not user data); playback
    /// states, playlist entries, and queue rows are filtered to the exported
    /// items so no dangling references are written.
    public func snapshot(
        in context: ModelContext,
        settings: AppSettingsStore? = nil,
        exportedAt: Date = Date(),
        appVersion: String? = nil
    ) throws -> BackupDocument {
        let benchmarkRaw = MediaSource.benchmark.rawValue
        let items = try context.fetch(FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.sourceRaw != benchmarkRaw }
        ))
        let itemIDs = Set(items.map(\.id))

        let collections = try context.fetch(FetchDescriptor<MediaCollection>())
        let playlists = try context.fetch(FetchDescriptor<Playlist>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        let playlistEntries = try context.fetch(FetchDescriptor<PlaylistEntry>(
            sortBy: [SortDescriptor(\.position)]
        ))
        let states = try context.fetch(FetchDescriptor<PlaybackState>())
        let queueRows = try context.fetch(FetchDescriptor<QueueEntry>(
            sortBy: [SortDescriptor(\.position)]
        ))

        let queueStateKey = QueueManager.stateKey
        var stateDescriptor = FetchDescriptor<QueueState>(
            predicate: #Predicate { $0.key == queueStateKey }
        )
        stateDescriptor.fetchLimit = 1
        let queueState = try context.fetch(stateDescriptor).first

        var entriesByPlaylist: [UUID: [BackupPlaylistEntry]] = [:]
        for entry in playlistEntries where itemIDs.contains(entry.itemID) {
            entriesByPlaylist[entry.playlistID, default: []]
                .append(BackupPlaylistEntry(itemID: entry.itemID, position: entry.position))
        }

        let backupPlaylists = playlists.map { playlist in
            BackupPlaylist(
                id: playlist.id,
                name: playlist.name,
                sortOrder: playlist.sortOrder,
                entries: (entriesByPlaylist[playlist.id] ?? [])
                    .sorted { $0.position < $1.position }
            )
        }

        let backupStates = states.compactMap { state -> BackupPlaybackState? in
            guard itemIDs.contains(state.itemID) else { return nil }
            return BackupPlaybackState(
                itemID: state.itemID,
                position: state.position,
                duration: state.duration,
                isFinished: state.isFinished,
                playCount: state.playCount,
                lastPlayedAt: state.lastPlayedAt,
                updatedAt: state.updatedAt
            )
        }

        let includedQueueRows = queueRows.filter { itemIDs.contains($0.itemID) }
        let queue: BackupQueueState?
        if !includedQueueRows.isEmpty || queueState != nil {
            queue = BackupQueueState(
                entries: includedQueueRows.map {
                    BackupQueueEntry(itemID: $0.itemID, position: $0.position)
                },
                currentItemID: queueState?.currentItemID.flatMap {
                    itemIDs.contains($0) ? $0 : nil
                },
                shuffleEnabled: queueState?.shuffleEnabled ?? false,
                repeatModeRaw: queueState?.repeatModeRaw ?? QueueRepeatMode.off.rawValue,
                shuffleOrder: (queueState?.shuffleOrderRaw ?? "")
                    .split(separator: ",")
                    .compactMap { UUID(uuidString: String($0)) }
                    .filter { itemIDs.contains($0) }
            )
        } else {
            queue = nil
        }

        return BackupDocument(
            schemaVersion: BackupDocument.currentSchemaVersion,
            appVersion: appVersion ?? Self.currentAppVersion,
            exportedAt: exportedAt,
            items: items.map { item in
                BackupItem(
                    id: item.id,
                    title: item.title,
                    sortTitle: item.sortTitle,
                    originalFileName: item.originalFileName,
                    relativePath: item.relativePath,
                    relativeFolderPath: item.relativeFolderPath,
                    kindRaw: item.kindRaw,
                    fileExtension: item.fileExtension,
                    byteSize: item.byteSize,
                    durationSeconds: item.durationSeconds,
                    addedAt: item.addedAt,
                    folderName: item.folderName,
                    sourceRaw: item.sourceRaw,
                    sourceName: item.sourceName,
                    fingerprint: item.fingerprint,
                    collectionID: item.collectionID,
                    artworkKey: item.artworkKey,
                    importSessionID: item.importSessionID,
                    isMissing: item.isMissing,
                    isFavorite: item.isFavorite,
                    notes: item.notes
                )
            },
            collections: collections.map {
                BackupCollection(id: $0.id, name: $0.name, sortOrder: $0.sortOrder)
            },
            playlists: backupPlaylists,
            playbackStates: backupStates,
            queue: queue,
            settings: settings.map { BackupSettings(store: $0) }
        )
    }

    // MARK: - Restore

    /// Restores a backup document into the CURRENT library. Nothing existing
    /// is ever deleted:
    ///
    /// - Items match by `id` first, then by fingerprint (SHA-256), mirroring
    ///   how `LibraryService.commit` re-links re-imported content. A match
    ///   keeps the existing row untouched; only unknown items are inserted.
    /// - Restored rows get `isMissing = !fileExists(relativePath)`.
    /// - Collections match by id, then by normalized name; otherwise created.
    /// - Playlists match by name: a matched playlist only gains entries it
    ///   does not already have (appended at the end); an unmatched name
    ///   creates a new playlist with a fresh id.
    /// - Playback states are written when the item exists; an existing state
    ///   is overwritten only when the backup's `updatedAt` is strictly newer.
    /// - The queue section (if present and non-empty) replaces the persisted
    ///   queue: the queue is playback state, not library data, and merging
    ///   two orderings is meaningless. Entries referencing unknown items are
    ///   dropped.
    /// - Settings, when present, are applied through `AppSettingsStore`.
    ///
    /// Playlist/queue entry ids are regenerated (their columns are unique);
    /// item and collection ids are preserved so repeated restores of the same
    /// backup stay idempotent.
    @discardableResult
    public func restore(
        _ document: BackupDocument,
        into context: ModelContext,
        settings: AppSettingsStore? = nil
    ) throws -> BackupRestoreResult {
        guard document.schemaVersion == BackupDocument.currentSchemaVersion else {
            throw BackupError.unsupportedVersion(found: document.schemaVersion)
        }
        var result = BackupRestoreResult()

        // Existing items indexed by id and fingerprint.
        var itemByID: [UUID: MediaItem] = [:]
        var itemByFingerprint: [String: MediaItem] = [:]
        for item in try context.fetch(FetchDescriptor<MediaItem>()) {
            itemByID[item.id] = item
            if let fingerprint = item.fingerprint {
                itemByFingerprint[fingerprint] = item
            }
        }

        // Collections indexed by id and normalized name.
        var collectionByID: [UUID: MediaCollection] = [:]
        var collectionByNameKey: [String: MediaCollection] = [:]
        for collection in try context.fetch(FetchDescriptor<MediaCollection>()) {
            collectionByID[collection.id] = collection
            collectionByNameKey[collection.nameKey] = collection
        }

        // backup collection id → library collection id
        var collectionIDMap: [UUID: UUID] = [:]
        for backup in document.collections {
            if let existing = collectionByID[backup.id] {
                collectionIDMap[backup.id] = existing.id
                continue
            }
            let nameKey = MediaCollection.normalizedKey(for: backup.name)
            if let existing = collectionByNameKey[nameKey] {
                collectionIDMap[backup.id] = existing.id
                continue
            }
            let collection = MediaCollection(
                id: backup.id,
                name: backup.name,
                nameKey: nameKey,
                sortOrder: backup.sortOrder
            )
            context.insert(collection)
            collectionByID[backup.id] = collection
            collectionByNameKey[nameKey] = collection
            collectionIDMap[backup.id] = collection.id
            result.collectionsRestored += 1
        }

        // Items. `itemIDMap` maps every backup item id to the library item id
        // its dependent rows must reference (identity for id matches and
        // restores, the existing row's id for fingerprint matches).
        var itemIDMap: [UUID: UUID] = [:]
        for backup in document.items {
            if itemByID[backup.id] != nil {
                itemIDMap[backup.id] = backup.id
                result.itemsMatched += 1
                continue
            }
            if let fingerprint = backup.fingerprint,
               let existing = itemByFingerprint[fingerprint] {
                // Same content, different identity: keep the existing row and
                // reconnect dependents to it, exactly like the import relink.
                itemIDMap[backup.id] = existing.id
                result.itemsMatched += 1
                continue
            }
            let isMissing = !fileExists(relativePath: backup.relativePath)
            let item = MediaItem(
                id: backup.id,
                title: backup.title,
                sortTitle: backup.sortTitle,
                originalFileName: backup.originalFileName,
                relativePath: backup.relativePath,
                relativeFolderPath: backup.relativeFolderPath,
                kind: MediaKind(rawValue: backup.kindRaw) ?? .audio,
                fileExtension: backup.fileExtension,
                byteSize: backup.byteSize,
                durationSeconds: backup.durationSeconds,
                addedAt: backup.addedAt,
                folderName: backup.folderName,
                source: MediaSource(rawValue: backup.sourceRaw) ?? .imported,
                sourceName: backup.sourceName,
                fingerprint: backup.fingerprint,
                collectionID: backup.collectionID.flatMap { collectionIDMap[$0] },
                artworkKey: backup.artworkKey,
                importSessionID: backup.importSessionID,
                isMissing: isMissing,
                isFavorite: backup.isFavorite,
                notes: backup.notes
            )
            context.insert(item)
            itemByID[backup.id] = item
            if let fingerprint = backup.fingerprint {
                itemByFingerprint[fingerprint] = item
            }
            itemIDMap[backup.id] = backup.id
            result.itemsRestored += 1
            if isMissing {
                result.itemsMissingMedia += 1
            }
        }

        // Playback progress, newer-wins.
        for backup in document.playbackStates {
            guard let itemID = itemIDMap[backup.itemID] else {
                result.skipped += 1
                continue
            }
            var descriptor = FetchDescriptor<PlaybackState>(
                predicate: #Predicate { $0.itemID == itemID }
            )
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                guard backup.updatedAt > existing.updatedAt else { continue }
                existing.position = backup.position
                existing.duration = backup.duration
                existing.isFinished = backup.isFinished
                existing.playCount = backup.playCount
                existing.lastPlayedAt = backup.lastPlayedAt
                existing.updatedAt = backup.updatedAt
                result.progressUpdated += 1
            } else {
                context.insert(PlaybackState(
                    itemID: itemID,
                    position: backup.position,
                    duration: backup.duration,
                    isFinished: backup.isFinished,
                    playCount: backup.playCount,
                    lastPlayedAt: backup.lastPlayedAt,
                    updatedAt: backup.updatedAt
                ))
                result.progressUpdated += 1
            }
        }

        // Playlists, merged by name.
        var playlistByName: [String: Playlist] = [:]
        for playlist in try context.fetch(FetchDescriptor<Playlist>()) {
            playlistByName[playlist.name] = playlist
        }
        var nextSortOrder = (playlistByName.values.map(\.sortOrder).max() ?? -1) + 1
        for backup in document.playlists {
            let target: Playlist
            if let existing = playlistByName[backup.name] {
                target = existing
                result.playlistsMerged += 1
            } else {
                // Fresh id: Playlist.id is unique, and a colliding backup id
                // must never block insertion.
                target = Playlist(
                    name: backup.name,
                    sortOrder: nextSortOrder
                )
                nextSortOrder += 1
                context.insert(target)
                playlistByName[backup.name] = target
                result.playlistsCreated += 1
            }

            let playlistID = target.id
            let existingEntries = try context.fetch(FetchDescriptor<PlaylistEntry>(
                predicate: #Predicate { $0.playlistID == playlistID },
                sortBy: [SortDescriptor(\.position)]
            ))
            var present = Set(existingEntries.map(\.itemID))
            var position = (existingEntries.map(\.position).max() ?? -1) + 1
            for entry in backup.entries.sorted(by: { $0.position < $1.position }) {
                guard let itemID = itemIDMap[entry.itemID] else {
                    result.skipped += 1
                    continue
                }
                guard present.insert(itemID).inserted else { continue }
                context.insert(PlaylistEntry(
                    playlistID: playlistID,
                    itemID: itemID,
                    position: position
                ))
                position += 1
                result.playlistEntriesAdded += 1
            }
        }

        // Queue state (replace, see doc comment). Skipped when the backup has
        // no usable queue section so partial backups cannot wipe the current
        // queue.
        if let backupQueue = document.queue, !backupQueue.entries.isEmpty {
            var orderedIDs: [UUID] = []
            var seen = Set<UUID>()
            for entry in backupQueue.entries.sorted(by: { $0.position < $1.position }) {
                guard let itemID = itemIDMap[entry.itemID] else {
                    result.skipped += 1
                    continue
                }
                if seen.insert(itemID).inserted {
                    orderedIDs.append(itemID)
                }
            }

            for row in try context.fetch(FetchDescriptor<QueueEntry>()) {
                context.delete(row)
            }
            for (index, itemID) in orderedIDs.enumerated() {
                context.insert(QueueEntry(itemID: itemID, position: index))
            }

            let queueStateKey = QueueManager.stateKey
            var descriptor = FetchDescriptor<QueueState>(
                predicate: #Predicate { $0.key == queueStateKey }
            )
            descriptor.fetchLimit = 1
            let state: QueueState
            if let existing = try context.fetch(descriptor).first {
                state = existing
            } else {
                state = QueueState()
                context.insert(state)
            }
            state.currentItemID = backupQueue.currentItemID
                .flatMap { itemIDMap[$0] }
                .flatMap { orderedIDs.contains($0) ? $0 : nil } ?? orderedIDs.first
            state.shuffleEnabled = backupQueue.shuffleEnabled
            state.repeatModeRaw = QueueRepeatMode(rawValue: backupQueue.repeatModeRaw)?
                .rawValue ?? QueueRepeatMode.off.rawValue
            state.shuffleOrderRaw = backupQueue.shuffleOrder
                .compactMap { itemIDMap[$0] }
                .filter { orderedIDs.contains($0) }
                .map(\.uuidString)
                .joined(separator: ",")
            state.updatedAt = Date()
        }

        if let settings, let backupSettings = document.settings {
            backupSettings.apply(to: settings)
        }

        try context.save()
        return result
    }

    // MARK: - File I/O

    /// Writes the document as UTF-8 JSON into a temp file the share sheet can
    /// present. The file name follows `LocalPod-backup-YYYY-MM-DD.json`.
    @discardableResult
    public static func exportURL(
        _ document: BackupDocument,
        fileName: String? = nil,
        now: Date = Date()
    ) throws -> URL {
        let name = fileName ?? defaultFileName(now: now)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
        do {
            try encodedJSON(document).write(to: url, options: .atomic)
        } catch {
            throw BackupError.writeFailed(error.localizedDescription)
        }
        return url
    }

    public static func defaultFileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "LocalPod-backup-\(formatter.string(from: now)).json"
    }

    public static func encodedJSON(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        do {
            return try encoder.encode(document)
        } catch {
            throw BackupError.writeFailed(error.localizedDescription)
        }
    }

    /// Reads and validates a backup file. The URL may come from the document
    /// picker, so security-scoped access is started around the read.
    public static func readDocument(from url: URL) throws -> BackupDocument {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupError.readFailed(error.localizedDescription)
        }
        let document = try decode(data)
        guard document.schemaVersion == BackupDocument.currentSchemaVersion else {
            throw BackupError.unsupportedVersion(found: document.schemaVersion)
        }
        return document
    }

    /// Pure decoding: corrupt JSON and undecodable payloads surface as
    /// `.corruptJSON` with a localized message; the schema version is checked
    /// separately by `readDocument` (and defensively by `restore`).
    public static func decode(_ data: Data) throws -> BackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(BackupDocument.self, from: data)
        } catch {
            throw BackupError.corruptJSON
        }
    }

    private func fileExists(relativePath: String) -> Bool {
        guard let url = try? storage.url(forRelativePath: relativePath) else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static var currentAppVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
        return "\(version) (\(build))"
    }
}
