import Foundation
import SwiftData
import XCTest
@testable import LocalPodKit

@MainActor
final class SampleContentTests: XCTestCase {
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
        return Environment(
            root: root,
            storage: storage,
            library: library,
            importService: FolderImportService(storage: storage, library: library),
            container: try LocalPodStore.makeContainer(inMemory: true)
        )
    }

    /// Three short, byte-distinct files. The production set is bundled TTS
    /// audio; tests only need the same folder/collection contract.
    private func makeSampleFolder(in root: TemporaryDirectory) throws -> URL {
        let folder = root.url.appendingPathComponent("SampleContent", isDirectory: true)
        try root.write("SampleContent/01 欢迎使用.m4a", bytes: 1_024)
        try root.write("SampleContent/02 专注呼吸.m4a", bytes: 2_048)
        try root.write("SampleContent/03 睡前放松.m4a", bytes: 3_072)
        return folder
    }

    private func importSamples(
        _ folder: URL,
        in env: Environment,
        artwork: Data? = Data(repeating: 0xAB, count: 64)
    ) async throws -> FolderImportResult {
        try await env.importService.importFolder(
            rootURL: folder,
            source: .sample,
            rootName: ImportSample.collectionName,
            collectionName: ImportSample.collectionName,
            in: env.context,
            probe: FakeMediaProbe(artwork: artwork)
        )
    }

    private func sampleItems(in env: Environment) throws -> [MediaItem] {
        try env.context.fetch(FetchDescriptor<MediaItem>())
            .filter { $0.source == .sample }
    }

    func testSampleSourcePersistsRawValueAndDisplayName() throws {
        let env = try makeEnvironment()
        XCTAssertEqual(MediaSource.sample.rawValue, "sample")
        XCTAssertEqual(MediaSource(rawValue: "sample"), .sample)
        XCTAssertEqual(
            MediaSource.sample.displayName(locale: Locale(identifier: "zh-Hans")),
            "示例"
        )
        XCTAssertEqual(
            MediaSource.sample.displayName(locale: Locale(identifier: "en")),
            "Sample"
        )

        env.context.insert(MediaItem(
            title: "持久化示例",
            relativePath: "Media/sample.m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 128,
            source: .sample,
            sourceName: ImportSample.collectionName
        ))
        try env.context.save()

        let stored = try XCTUnwrap(
            try env.context.fetch(FetchDescriptor<MediaItem>()).first
        )
        XCTAssertEqual(stored.sourceRaw, "sample")
        XCTAssertEqual(stored.source, .sample)
        XCTAssertEqual(
            stored.source.displayName(locale: Locale(identifier: "zh-Hans")),
            "示例"
        )
        XCTAssertEqual(stored.sourceName, ImportSample.collectionName)
    }

    func testDeleteSamplesCascadesRowsAndFilesButKeepsNormalItems() async throws {
        let env = try makeEnvironment()
        let folder = try makeSampleFolder(in: env.root)
        let result = try await importSamples(folder, in: env)
        XCTAssertEqual(result.report.importedCount, 3)
        XCTAssertEqual(result.report.source, .sample)
        XCTAssertEqual(result.commit.collectionName, ImportSample.collectionName)

        let items = try sampleItems(in: env)
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy { $0.sourceRaw == "sample" })

        let mediaURLs = try items.map { try env.storage.url(forRelativePath: $0.relativePath) }
        let artworkURLs = try items.map {
            try env.storage.artworkURL(forKey: XCTUnwrap($0.artworkKey))
        }
        XCTAssertEqual(Set(mediaURLs.map(\.path)).count, 3)
        XCTAssertTrue(mediaURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(artworkURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        for (index, item) in items.enumerated() {
            env.context.insert(PlaybackState(
                itemID: item.id,
                position: Double(index + 1),
                duration: 12.5
            ))
            env.context.insert(QueueEntry(itemID: item.id, position: index))
            env.context.insert(PlaylistEntry(
                playlistID: UUID(),
                itemID: item.id,
                position: index
            ))
        }
        let playlist = Playlist(name: "示例播放列表")
        env.context.insert(playlist)
        for (index, item) in items.enumerated() {
            env.context.insert(PlaylistEntry(
                playlistID: playlist.id,
                itemID: item.id,
                position: index
            ))
        }
        env.context.insert(QueueState(
            currentItemID: items[0].id,
            shuffleEnabled: true,
            shuffleOrder: items.map(\.id)
        ))

        // A normal import must survive a sample purge even though it also has
        // playback state and a queue row.
        let mediaRoot = try env.storage.mediaRootURL()
        let normalURL = mediaRoot.appendingPathComponent("normal.m4a")
        try Data(repeating: 0x44, count: 64).write(to: normalURL)
        let normal = MediaItem(
            title: "用户导入",
            relativePath: "Media/normal.m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 64,
            source: .files
        )
        env.context.insert(normal)
        env.context.insert(PlaybackState(itemID: normal.id, position: 1, duration: 10))
        env.context.insert(QueueEntry(itemID: normal.id, position: 10))
        try env.context.save()

        let deleteResult = try env.library.deleteSamples(in: env.context)

        XCTAssertEqual(deleteResult.deletedCount, 3)
        XCTAssertEqual(deleteResult.removedMediaFiles, 3)
        XCTAssertEqual(deleteResult.removedArtworkFiles, 3)
        XCTAssertEqual(deleteResult.removedPlaybackStates, 3)
        XCTAssertEqual(deleteResult.removedQueueEntries, 3)
        XCTAssertEqual(deleteResult.removedPlaylistEntries, 6)
        XCTAssertEqual(deleteResult.freedBytes, 1_024 + 2_048 + 3_072)

        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaItem>()), 1)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<PlaybackState>()), 1)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<QueueEntry>()), 1)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<PlaylistEntry>()), 0)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<Playlist>()), 1)

        for url in mediaURLs + artworkURLs {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: url.path),
                "sample file should be deleted: \(url.lastPathComponent)"
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: normalURL.path))

        let queueState = try XCTUnwrap(
            try env.context.fetch(FetchDescriptor<QueueState>()).first
        )
        XCTAssertNil(queueState.currentItemID)
        XCTAssertEqual(queueState.shuffleOrderRaw, "")

        // Calling it again is a no-op, not an error.
        let second = try env.library.deleteSamples(in: env.context)
        XCTAssertEqual(second.deletedCount, 0)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaItem>()), 1)
    }

    func testReimportAfterDeleteRestoresSamples() async throws {
        let env = try makeEnvironment()
        let folder = try makeSampleFolder(in: env.root)

        let first = try await importSamples(folder, in: env)
        XCTAssertEqual(first.report.importedCount, 3)
        _ = try env.library.deleteSamples(in: env.context)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaItem>()), 0)

        let second = try await importSamples(folder, in: env)
        XCTAssertEqual(second.report.importedCount, 3)
        XCTAssertEqual(second.report.duplicateCount, 0)
        XCTAssertEqual(second.commit.insertedCount, 3)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaItem>()), 3)
        XCTAssertEqual(try sampleItems(in: env).count, 3)

        let mediaRoot = try env.storage.mediaRootURL()
        let mediaFiles = try FileManager.default.contentsOfDirectory(
            at: mediaRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        XCTAssertEqual(mediaFiles.count, 3)
    }

    func testDedupPreventsDuplicatesWhileSamplesArePresent() async throws {
        let env = try makeEnvironment()
        let folder = try makeSampleFolder(in: env.root)

        let first = try await importSamples(folder, in: env)
        XCTAssertEqual(first.report.importedCount, 3)
        let second = try await importSamples(folder, in: env)

        XCTAssertEqual(second.report.importedCount, 0)
        XCTAssertEqual(second.report.duplicateCount, 3)
        XCTAssertEqual(second.commit.insertedCount, 0)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaItem>()), 3)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaCollection>()), 1)
        XCTAssertEqual(try sampleItems(in: env).count, 3)
    }
}

private enum ImportSample {
    static let collectionName = "示例内容"
}
