import Foundation
import SwiftData
import XCTest
@testable import LocalPodKit

@MainActor
final class LibraryServiceTests: XCTestCase {
    @MainActor
    private struct Environment {
        let root: TemporaryDirectory
        let storage: MediaStorage
        let library: LibraryService
        let importService: FolderImportService
        let container: ModelContainer

        var context: ModelContext { container.mainContext }
    }

    private func makeEnvironment() throws -> Environment {
        let root = try TemporaryDirectory()
        let storage = try MediaStorage(
            applicationSupportRoot: root.url.appendingPathComponent("Support"),
            cachesRoot: root.url.appendingPathComponent("Caches")
        )
        let library = LibraryService(storage: storage)
        let importService = FolderImportService(storage: storage, library: library)
        return Environment(
            root: root,
            storage: storage,
            library: library,
            importService: importService,
            container: try LocalPodStore.makeContainer(inMemory: true)
        )
    }

    func testImportThenReimportDeduplicatesAndKeepsOneCollection() async throws {
        let env = try makeEnvironment()
        let source = try TemporaryDirectory()
        try source.write("Season 1/Episode 1.m4a", bytes: 128)
        try source.write("Season 1/Episode 2.m4a", bytes: 256)
        try source.write("Season 2/Episode 3.mp4", bytes: 512)

        let first = try await env.importService.importFolder(
            rootURL: source.url,
            source: .files,
            rootName: "Course",
            collectionName: "Course",
            in: env.context,
            probe: FakeMediaProbe()
        )
        XCTAssertEqual(first.report.importedCount, 3)
        XCTAssertEqual(first.commit.insertedCount, 3)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaItem>()), 3)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaCollection>()), 1)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<ImportSession>()), 1)
        XCTAssertNotNil(first.reportPath)
        if let reportPath = first.reportPath {
            let reportURL = try env.storage.url(forRelativePath: reportPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        }

        let items = try env.context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(Set(items.map(\.relativeFolderPath)), ["Season 1", "Season 2"])
        XCTAssertTrue(items.allSatisfy { $0.fingerprint?.count == 64 })
        XCTAssertTrue(items.allSatisfy { $0.durationSeconds == 12.5 })
        XCTAssertTrue(items.allSatisfy { $0.collectionID != nil })
        for item in items {
            let url = try env.storage.url(forRelativePath: item.relativePath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }

        let second = try await env.importService.importFolder(
            rootURL: source.url,
            source: .files,
            rootName: "Course",
            collectionName: "Course",
            in: env.context,
            probe: FakeMediaProbe()
        )
        XCTAssertEqual(second.report.importedCount, 0)
        XCTAssertEqual(second.report.duplicateCount, 3)
        XCTAssertEqual(second.commit.insertedCount, 0)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaItem>()), 3)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaCollection>()), 1)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<ImportSession>()), 2)
    }

    func testDeleteMovesItemToTrashAndKeepsFileStaged() async throws {
        let env = try makeEnvironment()
        let source = try TemporaryDirectory()
        let artwork = Data(repeating: 0xAB, count: 64)
        try source.write("audio.m4a", bytes: 128)
        _ = try await env.importService.importFolder(
            rootURL: source.url,
            source: .files,
            rootName: "Single",
            in: env.context,
            probe: FakeMediaProbe(artwork: artwork)
        )

        let item = try XCTUnwrap(try env.context.fetch(FetchDescriptor<MediaItem>()).first)
        env.context.insert(PlaybackState(itemID: item.id, position: 12, duration: 60))
        try env.context.save()
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<PlaybackState>()), 1)
        let mediaURL = try env.storage.url(forRelativePath: item.relativePath)
        let artworkURL = try env.storage.artworkURL(forKey: XCTUnwrap(item.artworkKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: mediaURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artworkURL.path))

        let before = try env.library.storageBytes(in: env.context)
        let result = try env.library.delete(item, in: env.context)

        // Trash semantics: the row leaves the library, but media + artwork +
        // playback state stay until the trash is emptied.
        XCTAssertEqual(result.freedBytes, 128)
        XCTAssertTrue(result.movedToTrash)
        XCTAssertFalse(result.removedMediaFile)
        XCTAssertFalse(result.removedArtwork)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaItem>()), 0)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<TrashItem>()), 1)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<PlaybackState>()), 1)
        XCTAssertEqual(try env.library.storageBytes(in: env.context), before - 128)
        let trashRows = try env.context.fetch(FetchDescriptor<TrashItem>())
        XCTAssertEqual(trashRows.count, 1)
        let trashDir = try env.storage.trashItemURL(itemID: try XCTUnwrap(trashRows.first?.itemID))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: trashDir.path),
            "Media file must be staged under the trash directory"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: artworkURL.path))

        // Emptying the trash is the point of no return.
        let emptyResult = try TrashService(storage: env.storage).emptyTrash(in: env.context)
        XCTAssertEqual(emptyResult.purgedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artworkURL.path))
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<PlaybackState>()), 0)
    }

    func testDeleteHardRemovesRecordFileAndArtwork() async throws {
        let env = try makeEnvironment()
        let source = try TemporaryDirectory()
        let artwork = Data(repeating: 0xAB, count: 64)
        try source.write("audio.m4a", bytes: 128)
        _ = try await env.importService.importFolder(
            rootURL: source.url,
            source: .files,
            rootName: "Single",
            in: env.context,
            probe: FakeMediaProbe(artwork: artwork)
        )

        let item = try XCTUnwrap(try env.context.fetch(FetchDescriptor<MediaItem>()).first)
        env.context.insert(PlaybackState(itemID: item.id, position: 12, duration: 60))
        try env.context.save()
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<PlaybackState>()), 1)
        let mediaURL = try env.storage.url(forRelativePath: item.relativePath)
        let artworkURL = try env.storage.artworkURL(forKey: XCTUnwrap(item.artworkKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: mediaURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artworkURL.path))

        let before = try env.library.storageBytes(in: env.context)
        let result = try env.library.deleteHard(item, in: env.context)

        XCTAssertEqual(result.freedBytes, 128)
        XCTAssertTrue(result.removedMediaFile)
        XCTAssertTrue(result.removedArtwork)
        XCTAssertFalse(result.movedToTrash)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artworkURL.path))
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaItem>()), 0)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<PlaybackState>()), 0)
        XCTAssertEqual(try env.library.storageBytes(in: env.context), before - 128)
    }

    func testRelativePathSurvivesContainerMove() async throws {
        let env = try makeEnvironment()
        let source = try TemporaryDirectory()
        try source.write("portable.m4a", bytes: 128)
        _ = try await env.importService.importFolder(
            rootURL: source.url,
            source: .files,
            rootName: "Portable",
            in: env.context,
            probe: FakeMediaProbe()
        )
        let item = try XCTUnwrap(try env.context.fetch(FetchDescriptor<MediaItem>()).first)
        XCTAssertFalse(item.relativePath.hasPrefix("/"))

        let oldSupport = env.storage.applicationSupportRoot
        let newSupport = env.root.url.appendingPathComponent("MovedSupport")
        try FileManager.default.moveItem(at: oldSupport, to: newSupport)
        let movedStorage = try MediaStorage(
            applicationSupportRoot: newSupport,
            cachesRoot: env.root.url.appendingPathComponent("Caches")
        )
        let movedURL = try movedStorage.url(forRelativePath: item.relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.path))
    }

    func testReconcileMarksMissingCleansOrphansAndStaging() async throws {
        let env = try makeEnvironment()
        let source = try TemporaryDirectory()
        try source.write("one.m4a", bytes: 128)
        try source.write("two.m4a", bytes: 128 + 1)
        _ = try await env.importService.importFolder(
            rootURL: source.url,
            source: .files,
            rootName: "Cleanup",
            in: env.context,
            probe: FakeMediaProbe()
        )
        let items = try env.context.fetch(FetchDescriptor<MediaItem>(
            sortBy: [SortDescriptor(\.relativePath)]
        ))
        XCTAssertEqual(items.count, 2)

        let missingURL = try env.storage.url(forRelativePath: items[0].relativePath)
        try FileManager.default.removeItem(at: missingURL)

        let mediaRoot = try env.storage.mediaRootURL()
        try Data("orphan".utf8).write(to: mediaRoot.appendingPathComponent("orphan.m4a"))
        _ = try env.storage.newStagingSessionURL()

        let summary = try env.library.reconcile(in: env.context)

        XCTAssertEqual(summary.missingMarked, 1)
        XCTAssertEqual(summary.orphanMediaFilesRemoved, 1)
        XCTAssertEqual(summary.stagingSessionsRemoved, 1)
        XCTAssertTrue(items[0].isMissing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaRoot.appendingPathComponent("orphan.m4a").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: try env.storage.stagingRootURL().path).count, 0)
    }

    func testCollectionLookupIsCaseAndWhitespaceInsensitive() throws {
        let env = try makeEnvironment()
        let first = try env.library.findOrCreateCollection(named: "  My Course ", in: env.context)
        let second = try env.library.findOrCreateCollection(named: "my course", in: env.context)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.name, "My Course")
    }
}
