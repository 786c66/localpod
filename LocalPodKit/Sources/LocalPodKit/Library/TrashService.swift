import Foundation
import SwiftData

/// JSON snapshot of every `MediaItem` field needed to rebuild the row on
/// restore. Stored in `TrashItem.snapshotJSON`; also carries the playlist
/// membership the trashed item had, so restore can put those entries back.
public struct TrashItemSnapshot: Codable, Sendable, Equatable {
    public struct PlaylistEntrySnapshot: Codable, Sendable, Equatable {
        public let playlistID: UUID
        public let position: Int

        public init(playlistID: UUID, position: Int) {
            self.playlistID = playlistID
            self.position = position
        }
    }
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
    public var isFavorite: Bool
    public var notes: String?
    public var playlistEntries: [PlaylistEntrySnapshot]

    /// Captures the item plus its playlist membership before trashing.
    init(
        item: MediaItem,
        playlistEntries: [PlaylistEntrySnapshot] = []
    ) {
        self.init(
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
            isFavorite: item.isFavorite,
            notes: item.notes,
            playlistEntries: playlistEntries
        )
    }

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
        isFavorite: Bool,
        notes: String?,
        playlistEntries: [PlaylistEntrySnapshot] = []
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
        self.isFavorite = isFavorite
        self.notes = notes
        self.playlistEntries = playlistEntries
    }

    /// Rebuilds the MediaItem with the exact same identity, timestamps, and
    /// metadata it had before the trash. `isMissing` starts as requested so a
    /// restore of a file that no longer exists produces a missing row.
    func makeMediaItem(isMissing: Bool) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            sortTitle: sortTitle,
            originalFileName: originalFileName,
            relativePath: relativePath,
            relativeFolderPath: relativeFolderPath,
            kind: MediaKind(rawValue: kindRaw) ?? .audio,
            fileExtension: fileExtension,
            byteSize: byteSize,
            durationSeconds: durationSeconds,
            addedAt: addedAt,
            folderName: folderName,
            source: MediaSource(rawValue: sourceRaw) ?? .imported,
            sourceName: sourceName,
            fingerprint: fingerprint,
            collectionID: collectionID,
            artworkKey: artworkKey,
            importSessionID: importSessionID,
            isMissing: isMissing,
            isFavorite: isFavorite,
            notes: notes
        )
    }
}

public struct TrashDeleteResult: Sendable {
    public let title: String
    public let stagedMediaFile: Bool
    public let trashedPlaylistEntryCount: Int
}

public struct TrashRestoreResult: Sendable {
    public let title: String
    /// True when the media file made it back into `Media/`; false means only
    /// the DB row was restored and the item is marked missing.
    public let mediaFileRestored: Bool
    public let restoredPlaylistEntryCount: Int
}

public struct TrashPurgeResult: Sendable, Equatable {
    public let purgedCount: Int
    public let expiredPurgedCount: Int
    public let failedCount: Int
}

public enum TrashError: LocalizedError {
    case snapshotDecodeFailed
    case itemStillInLibrary
    case invalidStoredPath(String)

    public var errorDescription: String? {
        switch self {
        case .snapshotDecodeFailed:
            LocalPodLocalization.string("error.trash.snapshotDecode")
        case .itemStillInLibrary:
            LocalPodLocalization.string("error.trash.itemStillInLibrary")
        case .invalidStoredPath(let path):
            LocalPodLocalization.format(
                "error.mediaStorage.invalidRelativePath",
                path
            )
        }
    }
}

/// Trash / recently deleted. Moving an item to the trash removes the
/// `MediaItem` row (so every existing `@Query` view keeps working unchanged)
/// and hides the media file in `Application Support/Trash/<itemID>/`, keeping
/// artwork in Caches and `PlaybackState` untouched — a restore reconnects
/// everything by item id. Emptying the trash or purging expired rows is the
/// point of no return: it deletes media, staging directory, artwork, playback
/// state, and any queue rows that still referenced the item.
@MainActor
public final class TrashService {
    /// Trash retention. PLAN.md §2.2 allows 7-30 days; LocalPod keeps 30.
    public static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

    public let storage: MediaStorage

    public init(storage: MediaStorage = .live) {
        self.storage = storage
    }

    // MARK: - Move to trash

    /// Moves a library item to the trash. The MediaItem row is removed, the
    /// media file is staged in the trash directory, playlist membership is
    /// snapshotted and the rows removed, and queue rows are dropped (the queue
    /// must not reference an invisible item). Artwork and `PlaybackState` stay.
    ///
    /// Callers are responsible for `PlaybackSession.handleDeletedItem` so the
    /// in-memory queue/current item stays consistent, mirroring the old
    /// hard-delete flow.
    @discardableResult
    public func moveToTrash(
        _ item: MediaItem,
        in context: ModelContext
    ) throws -> TrashDeleteResult {
        let itemID = item.id
        let itemTitle = item.title
        let itemArtworkKey = item.artworkKey

        // Snapshot playlist membership first; the rows go away below and come
        // back (same playlistID + position) on restore.
        let playlistRows = try context.fetch(FetchDescriptor<PlaylistEntry>(
            predicate: #Predicate { $0.itemID == itemID }
        ))
        var snapshot = TrashItemSnapshot(item: item)
        snapshot.playlistEntries = playlistRows.map {
            TrashItemSnapshot.PlaylistEntrySnapshot(
                playlistID: $0.playlistID,
                position: $0.position
            )
        }

        let encoder = JSONEncoder()
        let snapshotJSON = try encoder.encode(snapshot)

        // Stage the media file. A missing file is not fatal: the trash row is
        // still created, and restore will simply produce a missing item.
        var stagedMedia = false
        let trashDir = try storage.trashItemURL(itemID: itemID)
        if let mediaURL = try? storage.url(forRelativePath: item.relativePath),
           FileManager.default.fileExists(atPath: mediaURL.path) {
            if !FileManager.default.fileExists(atPath: trashDir.path) {
                try FileManager.default.createDirectory(
                    at: trashDir,
                    withIntermediateDirectories: true
                )
            }
            let destination = trashDir
                .appendingPathComponent((item.relativePath as NSString).lastPathComponent)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: mediaURL, to: destination)
            stagedMedia = true
        }

        // Queue must not reference an invisible item.
        let queueRows = try context.fetch(FetchDescriptor<QueueEntry>(
            predicate: #Predicate { $0.itemID == itemID }
        ))
        for row in queueRows {
            context.delete(row)
        }

        for row in playlistRows {
            context.delete(row)
        }
        normalizePlaylistPositions(for: playlistRows.map(\.playlistID), in: context)

        context.delete(item)
        context.insert(TrashItem(
            itemID: itemID,
            title: itemTitle,
            snapshotJSON: snapshotJSON,
            deletedAt: Date(),
            expiresAt: Date().addingTimeInterval(Self.retentionInterval),
            artworkKey: itemArtworkKey
        ))
        try context.save()

        return TrashDeleteResult(
            title: itemTitle,
            stagedMediaFile: stagedMedia,
            trashedPlaylistEntryCount: playlistRows.count
        )
    }

    // MARK: - Restore

    /// Restores a trashed item: recreates the MediaItem (same id, same
    /// addedAt), moves the file back to `Media/`, restores playlist entries,
    /// and deletes the TrashItem row. A missing staged file still restores the
    /// row as `isMissing = true` so the existing missing-handling flow (mark,
    /// relink by fingerprint) takes over.
    ///
    /// Restoring into a library that already contains the item id would create
    /// a duplicate; that state is not reachable through the UI (delete moves
    /// to trash, dedup relinks instead of inserting), so it is treated as a
    /// programming error and thrown.
    @discardableResult
    public func restore(
        _ trashItem: TrashItem,
        in context: ModelContext
    ) throws -> TrashRestoreResult {
        let snapshot = try Self.decodeSnapshot(from: trashItem)
        let itemID = snapshot.id

        let duplicateDescriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.id == itemID }
        )
        if try context.fetchCount(duplicateDescriptor) > 0 {
            throw TrashError.itemStillInLibrary
        }

        var mediaRestored = false
        let trashDir = try storage.trashItemURL(itemID: itemID)
        let stagedURL = trashDir.appendingPathComponent(
            (snapshot.relativePath as NSString).lastPathComponent
        )
        if FileManager.default.fileExists(atPath: stagedURL.path) {
            let destinationURL = try storage.url(forRelativePath: snapshot.relativePath)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: stagedURL, to: destinationURL)
            try? FileManager.default.removeItem(at: trashDir)
            mediaRestored = true
        }

        context.insert(snapshot.makeMediaItem(isMissing: !mediaRestored))

        var restoredEntries = 0
        for entry in snapshot.playlistEntries {
            let playlistID = entry.playlistID
            let playlistDescriptor = FetchDescriptor<Playlist>(
                predicate: #Predicate { $0.id == playlistID }
            )
            guard try context.fetchCount(playlistDescriptor) > 0 else {
                // The playlist was deleted while the item sat in the trash.
                continue
            }
            context.insert(PlaylistEntry(
                playlistID: entry.playlistID,
                itemID: itemID,
                position: entry.position
            ))
            restoredEntries += 1
        }
        normalizePlaylistPositions(for: snapshot.playlistEntries.map(\.playlistID), in: context)

        context.delete(trashItem)
        try context.save()

        return TrashRestoreResult(
            title: snapshot.title,
            mediaFileRestored: mediaRestored,
            restoredPlaylistEntryCount: restoredEntries
        )
    }

    // MARK: - Purge

    /// Hard-deletes trash rows now (empty trash / per-item 彻底删除). This is
    /// the old `LibraryService.delete` cleanup: media file, artwork, playback
    /// state, queue rows, and (already-removed) playlist membership stay gone.
    @discardableResult
    public func purge(
        _ trashItem: TrashItem,
        in context: ModelContext
    ) throws -> Int {
        let snapshot = try Self.decodeSnapshot(from: trashItem)
        try Self.purgeSnapshot(snapshot, storage: storage, in: context)
        context.delete(trashItem)
        try context.save()
        return 1
    }

    /// Purges every expired trash row and optionally everything. Called at
    /// bootstrap BEFORE reconcile (expired media is staged outside `Media/`,
    /// so reconcile order does not strictly matter — purging first keeps the
    /// cleanup window tight).
    @discardableResult
    public func purgeExpired(
        now: Date = Date(),
        in context: ModelContext
    ) throws -> TrashPurgeResult {
        let rows = try context.fetch(FetchDescriptor<TrashItem>(
            predicate: #Predicate { $0.expiresAt <= now }
        ))
        var purged = 0
        var failures = 0
        for row in rows {
            do {
                _ = try purge(row, in: context)
                purged += 1
            } catch {
                failures += 1
            }
        }
        return TrashPurgeResult(
            purgedCount: purged,
            expiredPurgedCount: purged,
            failedCount: failures
        )
    }

    /// Empties the whole trash regardless of expiry.
    @discardableResult
    public func emptyTrash(in context: ModelContext) throws -> TrashPurgeResult {
        let rows = try context.fetch(FetchDescriptor<TrashItem>())
        var purged = 0
        var failures = 0
        for row in rows {
            do {
                _ = try purge(row, in: context)
                purged += 1
            } catch {
                failures += 1
            }
        }
        return TrashPurgeResult(
            purgedCount: purged,
            expiredPurgedCount: 0,
            failedCount: failures
        )
    }

    /// Shared cleanup of one trashed item: staging directory, media file (if
    /// it was never staged), artwork, playback state, and queue rows.
    static func purgeSnapshot(
        _ snapshot: TrashItemSnapshot,
        storage: MediaStorage,
        in context: ModelContext
    ) throws {
        let fileManager = FileManager.default
        let itemID = snapshot.id

        // Per-item staging directory (whole dir; stale siblings included).
        if let trashDir = try? storage.trashItemURL(itemID: itemID) {
            try? fileManager.removeItem(at: trashDir)
        }

        // File that was never staged (or staged under a legacy path).
        if let mediaURL = try? storage.url(forRelativePath: snapshot.relativePath) {
            try? fileManager.removeItem(at: mediaURL)
        }

        // Artwork is keyed by item id and shared with nothing else.
        if let artworkKey = snapshot.artworkKey,
           let artworkURL = try? storage.artworkURL(forKey: artworkKey) {
            try? fileManager.removeItem(at: artworkURL)
        }

        let states = try context.fetch(FetchDescriptor<PlaybackState>(
            predicate: #Predicate { $0.itemID == itemID }
        ))
        for state in states {
            context.delete(state)
        }
        let queueRows = try context.fetch(FetchDescriptor<QueueEntry>(
            predicate: #Predicate { $0.itemID == itemID }
        ))
        for row in queueRows {
            context.delete(row)
        }
        // Playlist entries were removed at trash time and are NOT restored by
        // purge; nothing to do here beyond defensive cleanup.
        let playlistRows = try context.fetch(FetchDescriptor<PlaylistEntry>(
            predicate: #Predicate { $0.itemID == itemID }
        ))
        for row in playlistRows {
            context.delete(row)
        }
    }

    // MARK: - Helpers

    static func decodeSnapshot(from trashItem: TrashItem) throws -> TrashItemSnapshot {
        do {
            // Default (deferred) date coding keeps addedAt/… bit-exact across a
            // trash/restore round trip.
            return try JSONDecoder().decode(TrashItemSnapshot.self, from: trashItem.snapshotJSON)
        } catch {
            throw TrashError.snapshotDecodeFailed
        }
    }

    /// Keeps playlist positions dense after removing/restoring entries so the
    /// existing ordering UI (move/rename flows) never sees gaps. Skips
    /// playlists that no longer exist.
    private func normalizePlaylistPositions(
        for playlistIDs: [UUID],
        in context: ModelContext
    ) {
        for playlistID in Set(playlistIDs) {
            let descriptor = FetchDescriptor<PlaylistEntry>(
                predicate: #Predicate { $0.playlistID == playlistID },
                sortBy: [SortDescriptor(\.position)]
            )
            let rows = (try? context.fetch(descriptor)) ?? []
            for (index, row) in rows.enumerated() where row.position != index {
                row.position = index
            }
        }
    }
}
