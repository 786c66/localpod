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
    public let removedMediaFile: Bool
    public let removedArtwork: Bool
}

public struct LibraryCleanupSummary: Sendable {
    public var missingMarked: Int = 0
    public var restored: Int = 0
    public var orphanMediaFilesRemoved: Int = 0
    public var stagingSessionsRemoved: Int = 0
    public var orphanArtworkFilesRemoved: Int = 0
    public var failures: [String] = []

    public var hasChanges: Bool {
        missingMarked > 0
            || restored > 0
            || orphanMediaFilesRemoved > 0
            || stagingSessionsRemoved > 0
            || orphanArtworkFilesRemoved > 0
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
        let displayName = trimmed.isEmpty ? "单文件" : trimmed
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
        let displayName = resolvedName.isEmpty ? "单文件" : resolvedName
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

    public func delete(
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
        context.delete(item)
        try context.save()

        return LibraryDeleteResult(
            title: title,
            freedBytes: freedBytes,
            removedMediaFile: removedMedia,
            removedArtwork: removedArtwork
        )
    }

    public func storageBytes(in context: ModelContext) throws -> Int64 {
        let items = try context.fetch(FetchDescriptor<MediaItem>())
        return items.reduce(into: Int64(0)) { $0 += $1.byteSize }
    }

    /// Startup / foreground maintenance:
    /// - mark records whose media file disappeared;
    /// - clear stale staging sessions;
    /// - remove media and artwork files with no DB record.
    public func reconcile(in context: ModelContext) throws -> LibraryCleanupSummary {
        var summary = LibraryCleanupSummary()
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
                    summary.failures.append("清理 staging 失败：\(url.lastPathComponent)")
                }
            }
        }

        if let mediaRoot = try? storage.mediaRootURL(),
           let mediaFiles = try? fileManager.contentsOfDirectory(
               at: mediaRoot,
               includingPropertiesForKeys: [.isRegularFileKey],
               options: [.skipsHiddenFiles]
           ) {
            for url in mediaFiles where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                let relative = try? storage.relativePath(for: url)
                if let relative, !referencedRelativePaths.contains(relative) {
                    do {
                        try fileManager.removeItem(at: url)
                        summary.orphanMediaFilesRemoved += 1
                    } catch {
                        summary.failures.append("清理孤儿媒体失败：\(url.lastPathComponent)")
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
                        summary.failures.append("清理孤儿封面失败：\(url.lastPathComponent)")
                    }
                }
            }
        }

        return summary
    }
}
