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
}
#endif
