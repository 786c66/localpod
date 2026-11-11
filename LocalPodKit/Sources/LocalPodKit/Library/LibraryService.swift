import Foundation
import SwiftData

public struct LibraryCommitResult: Sendable {
    public let insertedCount: Int
    public let relinkedCount: Int
    public let collectionID: UUID?
    public let collectionName: String

    public init(
        insertedCount: Int,
        relinkedCount: Int,
        collectionID: UUID?,
        collectionName: String
    ) {
        self.insertedCount = insertedCount
        self.relinkedCount = relinkedCount
        self.collectionID = collectionID
        self.collectionName = collectionName
    }
}

public struct LibraryDeleteResult: Sendable {
    public let title: String
    public let freedBytes: Int64
    /// False for a normal user delete: the media file was staged into the
    /// trash, not removed. True only for the legacy hard-delete path
    /// (`deleteHard`), which empty-trash/purge now handles.
    public let removedMediaFile: Bool
    public let removedArtwork: Bool
    /// Set when the delete went through the trash (the normal path).
    public let movedToTrash: Bool
    /// Playlist entries snapshotted and removed when the item was trashed.
    public let trashPlaylistEntryCount: Int

    public init(
        title: String,
        freedBytes: Int64,
        removedMediaFile: Bool,
        removedArtwork: Bool,
        movedToTrash: Bool = false,
        trashPlaylistEntryCount: Int = 0
    ) {
        self.title = title
        self.freedBytes = freedBytes
        self.removedMediaFile = removedMediaFile
        self.removedArtwork = removedArtwork
        self.movedToTrash = movedToTrash
        self.trashPlaylistEntryCount = trashPlaylistEntryCount
    }
}

public struct LibrarySampleDeleteResult: Sendable {
    public let deletedCount: Int
    public let freedBytes: Int64
    public let removedMediaFiles: Int
    public let removedArtworkFiles: Int
    public let removedPlaybackStates: Int
    public let removedQueueEntries: Int
    public let removedPlaylistEntries: Int
}

public struct LibraryCleanupSummary: Sendable {
    public var missingMarked: Int = 0
    public var restored: Int = 0
    public var orphanMediaFilesRemoved: Int = 0
    public var stagingSessionsRemoved: Int = 0
    public var orphanArtworkFilesRemoved: Int = 0
    /// Trash rows purged because their 30-day retention expired. Maintenance
    /// runs expired-purge before the file scans, so an expired item's artwork
    /// is removed before the orphan pass would otherwise report it.
    public var expiredTrashPurged: Int = 0
    public var failures: [String] = []

    public var hasChanges: Bool {
        missingMarked > 0
            || restored > 0
            || orphanMediaFilesRemoved > 0
            || stagingSessionsRemoved > 0
            || orphanArtworkFilesRemoved > 0
            || expiredTrashPurged > 0
            || !failures.isEmpty
    }

    /// Diagnostics show the cumulative effect of maintenance runs in this app
    /// session; a later clean pass must not hide what an earlier pass cleaned.
    public func merging(_ other: LibraryCleanupSummary) -> LibraryCleanupSummary {
        var result = self
        result.missingMarked += other.missingMarked
        result.restored += other.restored
        result.orphanMediaFilesRemoved += other.orphanMediaFilesRemoved
        result.stagingSessionsRemoved += other.stagingSessionsRemoved
        result.orphanArtworkFilesRemoved += other.orphanArtworkFilesRemoved
        result.expiredTrashPurged += other.expiredTrashPurged
        result.failures += other.failures
        return result
    }
}

@MainActor
public final class LibraryService {
    public let storage: MediaStorage

    public init(storage: MediaStorage = .live) {
        self.storage = storage
    }

    public func fingerprints(in context: ModelContext) throws -> Set<String> {
        let items = try context.fetch(FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.fingerprint != nil }
        ))
        return Set(items.compactMap(\.fingerprint))
    }

    public func missingFingerprints(in context: ModelContext) throws -> Set<String> {
        let items = try context.fetch(FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.isMissing && $0.fingerprint != nil }
        ))
        return Set(items.compactMap(\.fingerprint))
    }

    public func itemIndexByFingerprint(in context: ModelContext) throws -> [String: MediaItem] {
        let items = try context.fetch(FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.fingerprint != nil }
        ))
        var index: [String: MediaItem] = [:]
        for item in items {
            if let fingerprint = item.fingerprint {
                index[fingerprint] = item
            }
        }
        return index
    }

    public func findOrCreateCollection(
        named name: String,
        in context: ModelContext
    ) throws -> MediaCollection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty
            ? LocalPodLocalization.string("library.collection.singleFile")
            : trimmed
        let key = MediaCollection.normalizedKey(for: displayName)
        var descriptor = FetchDescriptor<MediaCollection>(
            predicate: #Predicate { $0.nameKey == key }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let collection = MediaCollection(name: displayName, nameKey: key)
        context.insert(collection)
        return collection
    }

    public func commit(
        report: ImportRunResult,
        collectionName: String?,
        in context: ModelContext
    ) throws -> LibraryCommitResult {
        let resolvedName = (collectionName ?? report.rootName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = resolvedName.isEmpty
            ? LocalPodLocalization.string("library.collection.singleFile")
            : resolvedName
        let hasImports = !report.importedFiles.isEmpty
        guard hasImports else {
            return LibraryCommitResult(
                insertedCount: 0,
                relinkedCount: 0,
                collectionID: nil,
                collectionName: displayName
            )
        }

        let collection = try findOrCreateCollection(named: displayName, in: context)
        collection.lastImportedAt = report.finishedAt

        let index = try itemIndexByFingerprint(in: context)
        var inserted = 0
        var relinked = 0
        var pendingSave = 0

        for imported in report.importedFiles {
            let relativePath = try storage.relativePath(for: imported.destinationURL)

            if imported.isRelink,
               let existing = index[imported.fingerprint] {
                existing.relativePath = relativePath
                existing.fileExtension = imported.fileExtension
                existing.byteSize = imported.byteSize
                existing.fileSize = imported.byteSize
                existing.durationSeconds = imported.durationSeconds
                existing.artworkKey = imported.artworkKey
                existing.isMissing = false
                existing.sourceName = report.rootName
                existing.importSessionID = report.sessionID
                if existing.collectionID == nil {
                    existing.collectionID = collection.id
                }
                relinked += 1
                pendingSave += 1
            } else {
                let item = MediaItem(
                    id: imported.id,
                    title: imported.title,
                    sortTitle: imported.title,
                    originalFileName: imported.originalFileName,
                    relativePath: relativePath,
                    relativeFolderPath: imported.relativeFolderPath,
                    kind: imported.kind,
                    fileExtension: imported.fileExtension,
                    byteSize: imported.byteSize,
                    durationSeconds: imported.durationSeconds,
                    folderName: collection.name,
                    source: report.source,
                    sourceName: report.rootName,
                    fingerprint: imported.fingerprint,
                    collectionID: collection.id,
                    artworkKey: imported.artworkKey,
                    importSessionID: report.sessionID
                )
                context.insert(item)
                inserted += 1
                pendingSave += 1
            }

            if pendingSave >= 100 {
                try context.save()
                pendingSave = 0
            }
        }

        if pendingSave > 0 {
            try context.save()
        }

        return LibraryCommitResult(
            insertedCount: inserted,
            relinkedCount: relinked,
            collectionID: collection.id,
            collectionName: collection.name
        )
    }

    /// Deletes a library item by moving it to the trash (P1 回收站): the
    /// MediaItem row disappears from every query, the media file is staged in
    /// `Application Support/Trash/<itemID>/`, and playlist membership is
    /// snapshotted so restore can put it back. See `TrashService`.
    @discardableResult
    public func delete(
        _ item: MediaItem,
        in context: ModelContext
    ) throws -> LibraryDeleteResult {
        let title = item.title
        let freedBytes = item.byteSize
        let result = try TrashService(storage: storage).moveToTrash(item, in: context)
        return LibraryDeleteResult(
            title: title,
            freedBytes: freedBytes,
            removedMediaFile: false,
            removedArtwork: false,
            movedToTrash: true,
            trashPlaylistEntryCount: result.trashedPlaylistEntryCount
        )
    }

    /// Legacy hard delete (file + artwork + playback/queue/playlist rows are
    /// gone immediately). Kept for tests and as the reference implementation;
    /// the app's user-facing delete path goes through the trash instead.
    @discardableResult
    public func deleteHard(
        _ item: MediaItem,
        in context: ModelContext
    ) throws -> LibraryDeleteResult {
        var removedMedia = false
        var removedArtwork = false

        if let url = try? storage.url(forRelativePath: item.relativePath),
           FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            removedMedia = true
        }
        if let artworkKey = item.artworkKey {
            if let url = try? storage.artworkURL(forKey: artworkKey),
               FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                removedArtwork = true
            }
        }

        let title = item.title
        let freedBytes = item.byteSize
        let itemID = item.id
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
        let playlistRows = try context.fetch(FetchDescriptor<PlaylistEntry>(
            predicate: #Predicate { $0.itemID == itemID }
        ))
        for row in playlistRows {
            context.delete(row)
        }
        context.delete(item)
        try context.save()

        return LibraryDeleteResult(
            title: title,
            freedBytes: freedBytes,
            removedMediaFile: removedMedia,
            removedArtwork: removedArtwork,
            movedToTrash: false,
            trashPlaylistEntryCount: 0
        )
    }

    /// Deletes every built-in sample item and its dependent rows/files in one
    /// transaction. Samples are ordinary library items once imported, so this
    /// intentionally reuses the same cleanup rules as `delete(_:in:)`.
    ///
    /// The source is matched through `sourceRaw`; it is not a schema change, so
    /// this works for stores created before M5.
    @discardableResult
    public func deleteSamples(
        in context: ModelContext
    ) throws -> LibrarySampleDeleteResult {
        let sampleRaw = MediaSource.sample.rawValue
        let items = try context.fetch(FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.sourceRaw == sampleRaw }
        ))
        guard !items.isEmpty else {
            return LibrarySampleDeleteResult(
                deletedCount: 0,
                freedBytes: 0,
                removedMediaFiles: 0,
                removedArtworkFiles: 0,
                removedPlaybackStates: 0,
                removedQueueEntries: 0,
                removedPlaylistEntries: 0
            )
        }

        let itemIDs = Set(items.map(\.id))
        let fileManager = FileManager.default
        var freedBytes: Int64 = 0
        var removedMediaFiles = 0
        var removedArtworkFiles = 0

        for item in items {
            freedBytes += item.byteSize

            if let url = try? storage.url(forRelativePath: item.relativePath),
               fileManager.fileExists(atPath: url.path),
               (try? fileManager.removeItem(at: url)) != nil {
                removedMediaFiles += 1
            }
            if let artworkKey = item.artworkKey,
               let url = try? storage.artworkURL(forKey: artworkKey),
               fileManager.fileExists(atPath: url.path),
               (try? fileManager.removeItem(at: url)) != nil {
                removedArtworkFiles += 1
            }
            context.delete(item)
        }

        var removedPlaybackStates = 0
        for state in try context.fetch(FetchDescriptor<PlaybackState>())
        where itemIDs.contains(state.itemID) {
            context.delete(state)
            removedPlaybackStates += 1
        }

        var removedQueueEntries = 0
        for entry in try context.fetch(FetchDescriptor<QueueEntry>())
        where itemIDs.contains(entry.itemID) {
            context.delete(entry)
            removedQueueEntries += 1
        }

        var removedPlaylistEntries = 0
        for entry in try context.fetch(FetchDescriptor<PlaylistEntry>())
        where itemIDs.contains(entry.itemID) {
            context.delete(entry)
            removedPlaylistEntries += 1
        }

        // QueueManager reloads entries at attach time, but the persisted
        // singleton must not keep pointing at a deleted sample or a stale
        // shuffle order.
        let queueStateKey = QueueManager.stateKey
        var stateDescriptor = FetchDescriptor<QueueState>(
            predicate: #Predicate { $0.key == queueStateKey }
        )
        stateDescriptor.fetchLimit = 1
        if let state = try context.fetch(stateDescriptor).first {
            var changed = false
            if let currentItemID = state.currentItemID,
               itemIDs.contains(currentItemID) {
                state.currentItemID = nil
                changed = true
            }
            let order = state.shuffleOrderRaw
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
                .filter { !itemIDs.contains($0) }
            let rewrittenOrder = order.map(\.uuidString).joined(separator: ",")
            if rewrittenOrder != state.shuffleOrderRaw {
                state.shuffleOrderRaw = rewrittenOrder
                changed = true
            }
            if changed {
                state.updatedAt = Date()
            }
        }

        try context.save()

        return LibrarySampleDeleteResult(
            deletedCount: items.count,
            freedBytes: freedBytes,
            removedMediaFiles: removedMediaFiles,
            removedArtworkFiles: removedArtworkFiles,
            removedPlaybackStates: removedPlaybackStates,
            removedQueueEntries: removedQueueEntries,
            removedPlaylistEntries: removedPlaylistEntries
        )
    }

    public func storageBytes(in context: ModelContext) throws -> Int64 {
        let items = try context.fetch(FetchDescriptor<MediaItem>())
        return items.reduce(into: Int64(0)) { $0 += $1.byteSize }
    }

    /// Startup / foreground maintenance:
    /// - purge trash rows whose retention expired (before any file scan, so a
    ///   purged item's artwork cannot be double-counted as an orphan);
    /// - mark records whose media file disappeared;
    /// - clear stale staging sessions;
    /// - remove media and artwork files with no DB record.
    ///
    /// The trash staging root (`Application Support/Trash`) is deliberately
    /// outside `Media/`, so the orphan-media scan never sees trashed files;
    /// `TrashService` owns that directory's lifecycle.
    public func reconcile(in context: ModelContext) throws -> LibraryCleanupSummary {
        var summary = LibraryCleanupSummary()

        // Expired trash first: a purged row's artwork is removed here, before
        // the orphan-artwork pass below runs.
        do {
            let trashResult = try TrashService(storage: storage).purgeExpired(in: context)
            summary.expiredTrashPurged = trashResult.purgedCount
            if trashResult.failedCount > 0 {
                summary.failures.append(LocalPodLocalization.format(
                    "error.maintenance.trashPurge",
                    trashResult.failedCount
                ))
            }
        } catch {
            summary.failures.append(LocalPodLocalization.format(
                "error.maintenance.trashPurge",
                error.localizedDescription
            ))
        }

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        var referencedRelativePaths = Set<String>()
        var referencedArtworkKeys = Set<String>()
        var needsSave = false

        for item in items {
            referencedRelativePaths.insert(item.relativePath)
            if let artworkKey = item.artworkKey {
                referencedArtworkKeys.insert(artworkKey)
            }
            let exists: Bool
            if let url = try? storage.url(forRelativePath: item.relativePath) {
                exists = FileManager.default.fileExists(atPath: url.path)
            } else {
                exists = false
            }
            if !exists, !item.isMissing {
                item.isMissing = true
                summary.missingMarked += 1
                needsSave = true
            } else if exists, item.isMissing {
                item.isMissing = false
                summary.restored += 1
                needsSave = true
            }
        }

        if needsSave {
            try context.save()
        }

        let fileManager = FileManager.default

        if let stagingRoot = try? storage.stagingRootURL(),
           let staging = try? fileManager.contentsOfDirectory(
               at: stagingRoot,
               includingPropertiesForKeys: [.isDirectoryKey],
               options: [.skipsHiddenFiles]
           ) {
            for url in staging {
                do {
                    try fileManager.removeItem(at: url)
                    summary.stagingSessionsRemoved += 1
                } catch {
                    summary.failures.append(LocalPodLocalization.format(
                        "error.maintenance.staging",
                        url.lastPathComponent
                    ))
                }
            }
        }

        if let mediaRoot = try? storage.mediaRootURL(),
           let mediaFiles = try? fileManager.contentsOfDirectory(
               at: mediaRoot,
               includingPropertiesForKeys: [.isRegularFileKey],
               options: [.skipsHiddenFiles]
           ) {
            // The trash staging root must never be scanned as orphan media,
            // even if it ever ends up inside the media root.
            let trashRoot = try? storage.trashRootURL().path
            for url in mediaFiles where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                if let trashRoot, url.standardizedFileURL.path.hasPrefix(trashRoot + "/") {
                    continue
                }
                let relative = try? storage.relativePath(for: url)
                if let relative, !referencedRelativePaths.contains(relative) {
                    do {
                        try fileManager.removeItem(at: url)
                        summary.orphanMediaFilesRemoved += 1
                    } catch {
                        summary.failures.append(LocalPodLocalization.format(
                            "error.maintenance.orphanMedia",
                            url.lastPathComponent
                        ))
                    }
                }
            }
        }

        if let artworkRoot = try? storage.artworkRootURL(),
           let artworkFiles = try? fileManager.contentsOfDirectory(
               at: artworkRoot,
               includingPropertiesForKeys: [.isRegularFileKey],
               options: [.skipsHiddenFiles]
           ) {
            for url in artworkFiles where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                if !referencedArtworkKeys.contains(url.lastPathComponent) {
                    do {
                        try fileManager.removeItem(at: url)
                        summary.orphanArtworkFilesRemoved += 1
                    } catch {
                        summary.failures.append(LocalPodLocalization.format(
                            "error.maintenance.orphanArtwork",
                            url.lastPathComponent
                        ))
                    }
                }
            }
        }

        return summary
    }
}
