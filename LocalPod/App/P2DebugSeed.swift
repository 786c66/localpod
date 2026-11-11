#if DEBUG
import Foundation
import SwiftData
import LocalPodKit

/// Deterministic fixtures for the P2 linked-folder UI tests. Only compiled in
/// Debug builds and only applied when the launch argument asks for it.
///
/// The seeded folder lives inside the app's own tmp/ directory, so no document
/// picker or security scope is involved; plain bookmarkData resolves fine for
/// app-internal URLs on the simulator.
@MainActor
enum P2DebugSeed {
    /// The seeded folder inside tmp/. A fixed name keeps the second launch's
    /// add-file seam deterministic across processes.
    static var folderURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("P2LinkedDemo", isDirectory: true)
    }

    static let rootName = "P2LinkedDemo"
    static let firstFileName = "Episode 01.m4a"
    static let secondFileName = "Episode 02.m4a"

    /// Record of the seeded folder, written next to the folder so the add-file
    /// seam can find it without touching the SwiftData store.
    private static var markerURL: URL {
        folderURL.deletingLastPathComponent()
            .appendingPathComponent("P2LinkedDemo.path")
    }

    /// --p2-seed-linked-folder: create tmp/P2LinkedDemo with one demo audio
    /// file and a LinkedFolder row. The first sync (user-initiated) imports
    /// that file. Returns true when the folder+row are ready.
    @discardableResult
    static func seedLinkedFolderIfRequested(in context: ModelContext) -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("--p2-seed-linked-folder")
            || ProcessInfo.processInfo.arguments.contains("--p2-stale-linked-folder") else {
            return false
        }
        let stale = ProcessInfo.processInfo.arguments.contains("--p2-stale-linked-folder")
        return seedLinkedFolder(in: context, removeDirectoryAfterSeeding: stale)
    }

    /// --p2-linked-folder-add-file: drop a second, different audio file into
    /// the previously seeded folder. Requires the same launch to seed (or have
    /// kept) the folder, so this also recreates the directory content if the
    /// first launch's files are gone but the marker remains.
    static func addFileToLinkedFolderIfRequested(in context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("--p2-linked-folder-add-file") else {
            return
        }
        guard ensureSeededFolderExists(in: context) else { return }
        copyDemoAudio(named: secondFileName)
    }

    // MARK: - Internals

    @discardableResult
    private static func seedLinkedFolder(
        in context: ModelContext,
        removeDirectoryAfterSeeding: Bool
    ) -> Bool {
        // A previous UI-test launch may have left the row; restart clean.
        removeExistingRows(in: context)
        try? FileManager.default.removeItem(at: folderURL)
        try? FileManager.default.removeItem(at: markerURL)
        guard copyDemoAudio(named: firstFileName) else { return false }

        guard let bookmark = try? LinkedFolderStore.makeBookmark(for: folderURL) else {
            return false
        }
        context.insert(LinkedFolder(
            bookmarkData: bookmark,
            rootName: rootName
        ))
        try? context.save()
        try? folderURL.path.write(to: markerURL, atomically: true, encoding: .utf8)

        if removeDirectoryAfterSeeding {
            // Simulate a source that disappeared after linking: the bookmark
            // can no longer resolve, so the UI must show the stale badge.
            try? FileManager.default.removeItem(at: folderURL)
        }
        return true
    }

    /// Ensures the seeded folder exists and a LinkedFolder row points at it,
    /// recreating both when a previous launch removed the directory.
    private static func ensureSeededFolderExists(in context: ModelContext) -> Bool {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: folderURL.path) {
            guard copyDemoAudio(named: firstFileName) else { return false }
        }

        let descriptor = FetchDescriptor<LinkedFolder>()
        let rows = (try? context.fetch(descriptor)) ?? []
        if let existing = rows.first(where: { $0.rootName == rootName }) {
            if let freshBookmark = try? LinkedFolderStore.makeBookmark(for: folderURL) {
                LinkedFolderStore.relink(existing, bookmarkData: freshBookmark)
                try? context.save()
            }
            return true
        }
        guard let bookmark = try? LinkedFolderStore.makeBookmark(for: folderURL) else {
            return false
        }
        context.insert(LinkedFolder(
            bookmarkData: bookmark,
            rootName: rootName
        ))
        try? context.save()
        return true
    }

    private static func removeExistingRows(in context: ModelContext) {
        let rows = (try? context.fetch(FetchDescriptor<LinkedFolder>())) ?? []
        for row in rows {
            context.delete(row)
        }
        if !rows.isEmpty {
            try? context.save()
        }
    }

    /// Copies the bundled demo audio with a unique trailing marker so SHA-256
    /// dedup treats each seeded file as distinct content (mimics the
    /// DemoFolderFactory approach).
    private static func copyDemoAudio(named name: String) -> Bool {
        guard let source = Bundle.main.url(forResource: "demo-audio", withExtension: "m4a"),
              var data = try? Data(contentsOf: source) else {
            return false
        }
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        data.append(Data("\nLocalPodP2Linked|\(name)|\(UUID().uuidString)\n".utf8))
        do {
            try data.write(to: folderURL.appendingPathComponent(name))
            return true
        } catch {
            return false
        }
    }

    // MARK: - Trash (回收站) fixtures

    static let trashedTitle = "回收站测试条目"
    static let expiredTitle = "回收站过期条目"

    private static func makeTrashSnapshot(
        title: String,
        itemID: UUID
    ) -> TrashItemSnapshot {
        TrashItemSnapshot(
            id: itemID,
            title: title,
            sortTitle: title,
            originalFileName: "\(itemID.uuidString).m4a",
            relativePath: "Media/\(itemID.uuidString).m4a",
            relativeFolderPath: "",
            kindRaw: MediaKind.audio.rawValue,
            fileExtension: "m4a",
            byteSize: 220_000,
            durationSeconds: 20,
            addedAt: Date().addingTimeInterval(-3_600),
            folderName: "P2 回收站",
            sourceRaw: MediaSource.imported.rawValue,
            sourceName: "P2 回收站",
            fingerprint: nil,
            collectionID: nil,
            artworkKey: nil,
            importSessionID: nil,
            isFavorite: false,
            notes: nil,
            playlistEntries: []
        )
    }

    private static func seedTrashItem(
        title: String,
        itemID: UUID,
        expiresAt: Date,
        stageMediaFile: Bool,
        in context: ModelContext
    ) {
        let encoder = JSONEncoder()
        guard let snapshotJSON = try? encoder.encode(
            makeTrashSnapshot(title: title, itemID: itemID)
        ) else {
            return
        }

        // Stage a real demo file into the trash directory so restore has
        // something to move back; the expired seed skips this (its purge must
        // succeed even with no staged file).
        let storage = MediaStorage.live
        if stageMediaFile,
           let trashDir = try? storage.trashItemURL(itemID: itemID),
           let source = Bundle.main.url(forResource: "demo-audio", withExtension: "m4a") {
            try? FileManager.default.createDirectory(
                at: trashDir,
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(
                at: trashDir.appendingPathComponent("\(itemID.uuidString).m4a")
            )
            try? FileManager.default.copyItem(
                at: source,
                to: trashDir.appendingPathComponent("\(itemID.uuidString).m4a")
            )
        }

        context.insert(TrashItem(
            itemID: itemID,
            title: title,
            snapshotJSON: snapshotJSON,
            deletedAt: Date().addingTimeInterval(-60),
            expiresAt: expiresAt,
            artworkKey: nil
        ))
        try? context.save()
    }

    /// --p2-seed-trash: one normal trash row (full retention) the UI test can
    /// restore. Restarting clean removes leftovers first.
    @discardableResult
    static func seedTrashIfRequested(in context: ModelContext) -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("--p2-seed-trash") else {
            return false
        }
        let itemID = UUID(uuidString: "44444444-4444-4444-8444-444444444401")!
        removeTrashRow(itemID: itemID, in: context)
        seedTrashItem(
            title: trashedTitle,
            itemID: itemID,
            expiresAt: Date().addingTimeInterval(TrashService.retentionInterval),
            stageMediaFile: true,
            in: context
        )
        return true
    }

    /// --p2-seed-expired-trash: one already-expired trash row. The launch
    /// bootstrap purge (reconcile → purgeExpired) must remove it before the
    /// first frame, so the trash UI shows the empty state.
    @discardableResult
    static func seedExpiredTrashIfRequested(in context: ModelContext) -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("--p2-seed-expired-trash") else {
            return false
        }
        let itemID = UUID(uuidString: "44444444-4444-4444-8444-444444444402")!
        removeTrashRow(itemID: itemID, in: context)
        seedTrashItem(
            title: expiredTitle,
            itemID: itemID,
            expiresAt: Date().addingTimeInterval(-60),
            stageMediaFile: false,
            in: context
        )
        return true
    }

    private static func removeTrashRow(itemID: UUID, in context: ModelContext) {
        let rows = (try? context.fetch(FetchDescriptor<TrashItem>(
            predicate: #Predicate { $0.itemID == itemID }
        ))) ?? []
        for row in rows {
            context.delete(row)
        }
        if !rows.isEmpty {
            try? context.save()
        }
    }
}
#endif
