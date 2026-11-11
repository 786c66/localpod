import Foundation
import SwiftData
import XCTest
@testable import LocalPodKit

@MainActor
final class LinkedFolderTests: XCTestCase {
    // MARK: - Bookmark roundtrip

    func testBookmarkRoundtripResolvesSamePath() throws {
        let root = try TemporaryDirectory()
        let sub = try root.write("Season 1/Episode 1.m4a", bytes: 64)
        let folderURL = sub.deletingLastPathComponent()

        let bookmark = try LinkedFolderStore.makeBookmark(for: folderURL)
        let access = try XCTUnwrap(LinkedFolderStore.resolve(bookmark).successValue)
        // Comparing standardized paths: bookmarks may normalize case/symlinks.
        XCTAssertEqual(
            access.url.standardizedFileURL.path,
            folderURL.standardizedFileURL.path
        )
        access.stop()
    }

    func testResolveStaleAfterFolderDeleted() throws {
        let root = try TemporaryDirectory()
        let file = try root.write("Gone/Episode 1.m4a", bytes: 64)
        let folderURL = file.deletingLastPathComponent()
        let bookmark = try LinkedFolderStore.makeBookmark(for: folderURL)
        try FileManager.default.removeItem(at: folderURL)

        let result = LinkedFolderStore.resolve(bookmark)
        guard case .failure(let error) = result else {
            return XCTFail("Expected .failure, got \(result)")
        }
        XCTAssertEqual(error, .staleBookmark)
        XCTAssertEqual(
            error.localizedDescription,
            LinkedFolderError.staleBookmark.localizedDescription
        )
    }

    func testResolveInvalidDataFails() {
        let result = LinkedFolderStore.resolve(Data("not a bookmark".utf8))
        guard case .failure(let error) = result else {
            return XCTFail("Expected .failure, got \(result)")
        }
        XCTAssertEqual(error, .staleBookmark)
    }

    func testErrorMessagesAreLocalized() {
        XCTAssertEqual(
            LinkedFolderError.staleBookmark.localizedDescription,
            LocalPodLocalization.string("linkedFolder.error.staleBookmark")
        )
        XCTAssertEqual(
            LinkedFolderError.unreadable.localizedDescription,
            LocalPodLocalization.string("linkedFolder.error.unreadable")
        )
        XCTAssertEqual(
            LinkedFolderError.accessDenied.localizedDescription,
            LocalPodLocalization.string("linkedFolder.error.accessDenied")
        )
        // zh/en parity: the English table must not fall back to the key.
        XCTAssertFalse(
            LocalPodLocalization.string("linkedFolder.error.staleBookmark", locale: Locale(identifier: "en"))
                .contains("linkedFolder.error")
        )
    }

    func testWithAccessStopsAccessExactlyOnce() throws {
        let root = try TemporaryDirectory()
        let file = try root.write("Folder/Episode 1.m4a", bytes: 64)
        let folderURL = file.deletingLastPathComponent()
        let bookmark = try LinkedFolderStore.makeBookmark(for: folderURL)
        let access = try XCTUnwrap(LinkedFolderStore.resolve(bookmark).successValue)

        nonisolated(unsafe) var stopCount = 0
        let forwarding = LinkedFolderStore.ResolvedAccess(
            url: access.url,
            stop: { stopCount += 1 }
        )
        let value = try forwarding.withAccess { url in
            url.lastPathComponent
        }
        XCTAssertEqual(value, "Folder")
        XCTAssertEqual(stopCount, 1)
    }

    // MARK: - Diff

    private func scanned(_ relativePath: String, bytes: Int64 = 100) -> ScannedFile {
        ScannedFile(
            url: URL(fileURLWithPath: "/tmp/source/\(relativePath)"),
            relativePath: relativePath,
            byteSize: bytes,
            kind: .audio,
            contentTypeIdentifier: "public.mpeg-4-audio"
        )
    }

    private func key(_ relativeFolderPath: String, _ fileName: String) -> String {
        LinkedFolderStore.existingSourceKey(
            relativeFolderPath: relativeFolderPath,
            originalFileName: fileName
        )
    }

    func testDiffNoChanges() {
        let existing: Set<String> = [key("", "Episode 1.m4a"), key("Season 1", "Episode 2.m4a")]
        let diff = LinkedFolderStore.diff(
            existingSourceKeys: existing,
            scannedFiles: [
                scanned("Episode 1.m4a"),
                scanned("Season 1/Episode 2.m4a")
            ]
        )
        XCTAssertTrue(diff.newFiles.isEmpty)
        XCTAssertTrue(diff.removedPaths.isEmpty)
    }

    func testDiffNewFile() {
        let existing: Set<String> = [key("", "Episode 1.m4a")]
        let diff = LinkedFolderStore.diff(
            existingSourceKeys: existing,
            scannedFiles: [
                scanned("Episode 1.m4a"),
                scanned("Episode 2.m4a")
            ]
        )
        XCTAssertEqual(diff.newFiles.map(\.relativePath), ["Episode 2.m4a"])
        XCTAssertTrue(diff.removedPaths.isEmpty)
    }

    func testDiffNewSubdirectory() {
        let existing: Set<String> = [key("", "Episode 1.m4a")]
        let diff = LinkedFolderStore.diff(
            existingSourceKeys: existing,
            scannedFiles: [
                scanned("Episode 1.m4a"),
                scanned("Season 2/Episode 3.m4a"),
                scanned("Season 2/Disc 1/Episode 4.m4a")
            ]
        )
        XCTAssertEqual(
            Set(diff.newFiles.map(\.relativePath)),
            ["Season 2/Episode 3.m4a", "Season 2/Disc 1/Episode 4.m4a"]
        )
        XCTAssertTrue(diff.removedPaths.isEmpty)
    }

    func testDiffRenamedFileIsNewAndRemoved() {
        let existing: Set<String> = [key("Season 1", "Episode 1.m4a")]
        let diff = LinkedFolderStore.diff(
            existingSourceKeys: existing,
            scannedFiles: [scanned("Season 1/Episode 1 (new name).m4a")]
        )
        XCTAssertEqual(diff.newFiles.map(\.relativePath), ["Season 1/Episode 1 (new name).m4a"])
        XCTAssertEqual(diff.removedPaths, ["Season 1/Episode 1.m4a"])
    }

    func testDiffRemovedFile() {
        let existing: Set<String> = [
            key("", "Episode 1.m4a"),
            key("", "Episode 2.m4a")
        ]
        let diff = LinkedFolderStore.diff(
            existingSourceKeys: existing,
            scannedFiles: [scanned("Episode 1.m4a")]
        )
        XCTAssertTrue(diff.newFiles.isEmpty)
        XCTAssertEqual(diff.removedPaths, ["Episode 2.m4a"])
    }

    func testDiffUnchangedFileIsNotReimportedEvenWhenContentPathDiffers() {
        // The sandbox copy path (relativePath on MediaItem) is NOT part of the
        // key — a re-scan of the same source file must not import again.
        let existing: Set<String> = [key("Season 1", "Episode 1.m4a")]
        let diff = LinkedFolderStore.diff(
            existingSourceKeys: existing,
            scannedFiles: [scanned("Season 1/Episode 1.m4a", bytes: 999)]
        )
        XCTAssertTrue(diff.newFiles.isEmpty)
        XCTAssertTrue(diff.removedPaths.isEmpty)
    }

    func testExistingSourceKeysFetchesByFolderName() throws {
        let container = try LocalPodStore.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(MediaItem(
            title: "A",
            sortTitle: "A",
            originalFileName: "Episode 1.m4a",
            relativePath: "Media/a.m4a",
            relativeFolderPath: "Season 1",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 10,
            folderName: "演示"
        ))
        context.insert(MediaItem(
            title: "B",
            sortTitle: "B",
            originalFileName: "Episode 2.m4a",
            relativePath: "Media/b.m4a",
            relativeFolderPath: "",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 10,
            folderName: "其他来源"
        ))
        try context.save()

        let keys = try LinkedFolderStore.existingSourceKeys(
            forLinkedFolderNamed: "演示",
            in: context
        )
        XCTAssertEqual(keys, ["Season 1/Episode 1.m4a"])
    }

    // MARK: - Row bookkeeping

    private func makeRow() throws -> (ModelContainer, LinkedFolder) {
        let container = try LocalPodStore.makeContainer(inMemory: true)
        let folder = LinkedFolder(
            bookmarkData: Data([1, 2, 3]),
            rootName: "演示"
        )
        container.mainContext.insert(folder)
        try container.mainContext.save()
        return (container, folder)
    }

    func testRecordScanUpdatesRowAndClearsStale() throws {
        let (container, folder) = try makeRow()
        folder.isStale = true

        LinkedFolderStore.recordScan(
            folder,
            importedCount: 3,
            removedCount: 2,
            scannedAt: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(folder.lastImportedCount, 3)
        XCTAssertEqual(folder.lastRemovedCount, 2)
        XCTAssertEqual(folder.lastScannedAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertFalse(folder.isStale)
        _ = container
    }

    func testMarkStaleAndRelink() throws {
        let (container, folder) = try makeRow()
        LinkedFolderStore.markStale(folder)
        XCTAssertTrue(folder.isStale)

        LinkedFolderStore.relink(folder, bookmarkData: Data([9, 9]))
        XCTAssertFalse(folder.isStale)
        XCTAssertEqual(folder.bookmarkData, Data([9, 9]))
        _ = container
    }

    func testLinkedFolderPersistsThroughInMemoryContainer() throws {
        let (container, folder) = try makeRow()
        let scannedAt = Date(timeIntervalSince1970: 1_735_000_000)
        LinkedFolderStore.recordScan(
            folder,
            importedCount: 1,
            removedCount: 0,
            scannedAt: scannedAt
        )

        let context = container.mainContext
        let rows = try context.fetch(FetchDescriptor<LinkedFolder>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.rootName, "演示")
        XCTAssertEqual(rows.first?.lastImportedCount, 1)
        XCTAssertEqual(rows.first?.lastScannedAt, scannedAt)
        XCTAssertTrue(rows.first?.enabled ?? false)
    }

    // MARK: - V4 → V5 migration

    func testV4StoreMigratesToV5AndAddsLinkedFolder() throws {
        let root = try TemporaryDirectory()
        let storeURL = root.url.appendingPathComponent("LocalPod.store")

        try makeV4Store(at: storeURL)
        let container = try openV5Store(at: storeURL)
        let context = container.mainContext

        // Pre-existing data survived the lightweight migration.
        let items = try context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "M3 item")
        let states = try context.fetch(FetchDescriptor<PlaybackState>())
        XCTAssertEqual(states.count, 1)

        // The new entity is usable right after migration.
        let folder = LinkedFolder(
            bookmarkData: Data([1]),
            rootName: "迁移后文件夹"
        )
        context.insert(folder)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LinkedFolder>()), 1)
    }

    private func makeV4Store(at url: URL) throws {
        let schema = Schema(versionedSchema: LocalPodSchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
        let context = container.mainContext
        let item = LocalPodSchemaV2.MediaItem(
            title: "M3 item",
            relativePath: "Media/m3.m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 777,
            durationSeconds: 60
        )
        context.insert(item)
        context.insert(LocalPodSchemaV3.PlaybackState(
            itemID: item.id,
            position: 5,
            duration: 60
        ))
        try context.save()
    }

    private func openV5Store(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LocalPodSchemaV5.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: LocalPodMigrationPlan.self,
            configurations: [configuration]
        )
    }
}

private extension Result {
    var successValue: Success? {
        if case .success(let value) = self { return value }
        return nil
    }
}
