import CryptoKit
import SwiftData
import XCTest
@testable import LocalPodKit

@MainActor
final class BackupServiceTests: XCTestCase {
    @MainActor
    private struct Environment {
        let root: TemporaryDirectory
        let storage: MediaStorage
        let container: ModelContainer

        var context: ModelContext { container.mainContext }
    }

    private func makeEnvironment() throws -> Environment {
        let root = try TemporaryDirectory()
        let storage = try MediaStorage(
            applicationSupportRoot: root.url.appendingPathComponent("Support"),
            cachesRoot: root.url.appendingPathComponent("Caches")
        )
        return Environment(
            root: root,
            storage: storage,
            container: try LocalPodStore.makeContainer(inMemory: true)
        )
    }

    /// Writes a real (distinct-content) media file into the environment's
    /// storage at `relativePath` so `fileExists(relativePath)` is true.
    private func stageMediaFile(
        _ relativePath: String,
        content: String,
        in env: Environment
    ) throws {
        let url = try env.storage.url(forRelativePath: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(content.utf8).write(to: url)
    }

    private func fingerprint(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func makeSettings(defaults: UserDefaults) -> AppSettingsStore {
        AppSettingsStore(
            defaults: defaults,
            keyPrefix: "localpod.backup.test.\(UUID().uuidString)."
        )
    }

    // MARK: - Round trip

    func testRoundTripIntoFreshContainerRestoresEverything() throws {
        let source = try makeEnvironment()
        let service = BackupService(storage: source.storage)

        // Collections, items with real files, playlist, progress, queue.
        let collection = MediaCollection(
            id: UUID(uuidString: "AAAA0000-0000-0000-0000-000000000001")!,
            name: "播客合集",
            nameKey: "播客合集",
            sortOrder: 3
        )
        source.context.insert(collection)

        let fileA = "Media/\(UUID().uuidString).m4a"
        let fileB = "Media/Season 1/\(UUID().uuidString).m4a"
        try stageMediaFile(fileA, content: "audio-a", in: source)
        try stageMediaFile(fileB, content: "audio-b", in: source)

        let itemA = MediaItem(
            id: UUID(uuidString: "BBBB0000-0000-0000-0000-000000000001")!,
            title: "第一集",
            originalFileName: "ep1.m4a",
            relativePath: fileA,
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 1000,
            durationSeconds: 60,
            folderName: "播客合集",
            source: .files,
            sourceName: "播客合集",
            fingerprint: fingerprint("audio-a"),
            collectionID: collection.id,
            isFavorite: true,
            notes: "备注甲"
        )
        let itemB = MediaItem(
            id: UUID(uuidString: "BBBB0000-0000-0000-0000-000000000002")!,
            title: "第二集",
            originalFileName: "ep2.m4a",
            relativePath: fileB,
            relativeFolderPath: "Season 1",
            kind: .video,
            fileExtension: "mp4",
            byteSize: 2000,
            durationSeconds: 120,
            folderName: "播客合集",
            source: .wifi,
            sourceName: "Wi-Fi",
            fingerprint: fingerprint("audio-b"),
            collectionID: collection.id
        )
        source.context.insert(itemA)
        source.context.insert(itemB)

        let playlist = Playlist(name: "通勤", sortOrder: 0)
        source.context.insert(playlist)
        source.context.insert(PlaylistEntry(
            playlistID: playlist.id, itemID: itemA.id, position: 0
        ))
        source.context.insert(PlaylistEntry(
            playlistID: playlist.id, itemID: itemB.id, position: 1
        ))

        source.context.insert(PlaybackState(
            itemID: itemB.id,
            position: 42.5,
            duration: 120,
            isFinished: false,
            playCount: 2,
            lastPlayedAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        ))

        source.context.insert(QueueEntry(itemID: itemB.id, position: 0))
        source.context.insert(QueueEntry(itemID: itemA.id, position: 1))
        source.context.insert(QueueState(
            currentItemID: itemB.id,
            shuffleEnabled: true,
            repeatMode: .all,
            shuffleOrder: [itemB.id, itemA.id]
        ))

        let defaultsSuite = "LocalPodBackupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let settingsStore = makeSettings(defaults: defaults)
        settingsStore.defaultRate = 1.5
        settingsStore.skipForwardSeconds = 30
        settingsStore.resumeEnabled = false
        settingsStore.autoPlayNext = false

        try source.context.save()

        let document = try service.snapshot(
            in: source.context,
            settings: settingsStore
        )

        // Encode → decode → restore into a FRESH container.
        let data = try backupJSONEncoder().encode(document)
        let decoded = try backupJSONDecoder().decode(BackupDocument.self, from: data)

        let target = try makeEnvironment()
        // The backup carries DATA only; re-stage the media files in the
        // target container the way a user re-importing the folder would.
        try stageMediaFile(fileA, content: "audio-a", in: target)
        try stageMediaFile(fileB, content: "audio-b", in: target)
        let targetService = BackupService(storage: target.storage)
        let targetDefaultsSuite = "LocalPodBackupTests.\(UUID().uuidString)"
        let targetDefaults = UserDefaults(suiteName: targetDefaultsSuite)!
        defer { targetDefaults.removePersistentDomain(forName: targetDefaultsSuite) }
        let targetSettings = makeSettings(defaults: targetDefaults)
        targetSettings.defaultRate = 1.0 // differs from the backup's 1.5

        let result = try targetService.restore(
            decoded,
            into: target.context,
            settings: targetSettings
        )

        XCTAssertEqual(result.itemsRestored, 2)
        XCTAssertEqual(result.itemsMatched, 0)
        XCTAssertEqual(result.itemsMissingMedia, 0, "both files were re-staged")
        XCTAssertEqual(result.collectionsRestored, 1)
        XCTAssertEqual(result.playlistsCreated, 1)
        XCTAssertEqual(result.playlistEntriesAdded, 2)
        XCTAssertEqual(result.progressUpdated, 1)
        XCTAssertEqual(result.skipped, 0)

        let restoredItems = try target.context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(Set(restoredItems.map(\.id)), [itemA.id, itemB.id])
        let restoredA = restoredItems.first { $0.id == itemA.id }
        let restoredB = restoredItems.first { $0.id == itemB.id }
        XCTAssertEqual(restoredA?.title, "第一集")
        XCTAssertEqual(restoredA?.relativePath, fileA)
        XCTAssertEqual(restoredA?.fingerprint, fingerprint("audio-a"))
        XCTAssertEqual(restoredA?.collectionID, collection.id)
        XCTAssertEqual(restoredA?.isFavorite, true)
        XCTAssertEqual(restoredA?.notes, "备注甲")
        XCTAssertEqual(restoredA?.isMissing, false)
        XCTAssertEqual(restoredA?.source, .files)
        XCTAssertEqual(restoredA?.durationSeconds, 60)
        XCTAssertEqual(restoredB?.kind, .video)
        XCTAssertEqual(restoredB?.relativeFolderPath, "Season 1")

        let restoredCollections = try target.context.fetch(FetchDescriptor<MediaCollection>())
        XCTAssertEqual(restoredCollections.count, 1)
        XCTAssertEqual(restoredCollections.first?.id, collection.id)
        XCTAssertEqual(restoredCollections.first?.name, "播客合集")
        XCTAssertEqual(restoredCollections.first?.sortOrder, 3)

        let restoredPlaylists = try target.context.fetch(FetchDescriptor<Playlist>())
        XCTAssertEqual(restoredPlaylists.count, 1)
        XCTAssertEqual(restoredPlaylists.first?.name, "通勤")
        let playlistService = PlaylistService(context: target.context)
        XCTAssertEqual(
            playlistService.itemIDs(in: restoredPlaylists[0]),
            [itemA.id, itemB.id]
        )
        XCTAssertEqual(
            playlistService.entries(in: restoredPlaylists[0]).map(\.position),
            [0, 1]
        )

        let restoredStates = try target.context.fetch(FetchDescriptor<PlaybackState>())
        XCTAssertEqual(restoredStates.count, 1)
        XCTAssertEqual(restoredStates.first?.itemID, itemB.id)
        XCTAssertEqual(restoredStates.first?.position ?? 0, 42.5, accuracy: 0.001)
        XCTAssertEqual(restoredStates.first?.duration ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(restoredStates.first?.isFinished, false)
        XCTAssertEqual(restoredStates.first?.playCount, 2)
        XCTAssertEqual(
            restoredStates.first?.lastPlayedAt,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(
            restoredStates.first?.updatedAt,
            Date(timeIntervalSince1970: 1_700_000_100)
        )

        let restoredQueue = try target.context.fetch(FetchDescriptor<QueueEntry>(
            sortBy: [SortDescriptor(\.position)]
        ))
        XCTAssertEqual(restoredQueue.map(\.itemID), [itemB.id, itemA.id])

        let queueStateKey = QueueManager.stateKey
        var stateDescriptor = FetchDescriptor<QueueState>(
            predicate: #Predicate { $0.key == queueStateKey }
        )
        stateDescriptor.fetchLimit = 1
        let restoredQueueState = try target.context.fetch(stateDescriptor).first
        XCTAssertEqual(restoredQueueState?.currentItemID, itemB.id)
        XCTAssertEqual(restoredQueueState?.shuffleEnabled, true)
        XCTAssertEqual(restoredQueueState?.repeatModeRaw, QueueRepeatMode.all.rawValue)

        XCTAssertEqual(targetSettings.defaultRate, 1.5, accuracy: 0.001)
        XCTAssertEqual(targetSettings.skipForwardSeconds, 30)
        XCTAssertEqual(targetSettings.resumeEnabled, false)
        XCTAssertEqual(targetSettings.autoPlayNext, false)
        XCTAssertEqual(targetSettings.signingReminderEnabled, true)
    }

    func testSnapshotExcludesBenchmarkRowsAndDanglingStates() throws {
        let env = try makeEnvironment()
        let service = BackupService(storage: env.storage)

        let kept = MediaItem(
            title: "保留",
            relativePath: "Media/keep.m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 10
        )
        let benchmark = MediaItem(
            title: "基准",
            relativePath: "Media/bench.m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 10,
            source: .benchmark
        )
        env.context.insert(kept)
        env.context.insert(benchmark)
        // Progress on a benchmark row and on a phantom item: neither exports.
        env.context.insert(PlaybackState(itemID: benchmark.id, position: 1))
        env.context.insert(PlaybackState(itemID: UUID(), position: 2))
        env.context.insert(QueueEntry(itemID: benchmark.id, position: 0))
        try env.context.save()

        let document = try service.snapshot(in: env.context)
        XCTAssertEqual(document.items.map(\.id), [kept.id])
        XCTAssertEqual(document.playbackStates, [])
        XCTAssertNil(
            document.queue,
            "no usable queue section: restoring it must not touch the live queue"
        )
    }

    // MARK: - Merge rules

    func testRestoreIntoNonEmptyLibraryKeepsExistingRowsAndMergesByName() throws {
        let backupEnv = try makeEnvironment()
        let backupService = BackupService(storage: backupEnv.storage)

        // Backup content: two items + one playlist + one progress row.
        let fileA = "Media/\(UUID().uuidString).m4a"
        let fileB = "Media/\(UUID().uuidString).m4a"
        try stageMediaFile(fileA, content: "merge-a", in: backupEnv)
        try stageMediaFile(fileB, content: "merge-b", in: backupEnv)

        let itemA = MediaItem(
            id: UUID(uuidString: "CCCC0000-0000-0000-0000-000000000001")!,
            title: "备份条目甲",
            relativePath: fileA,
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 10,
            fingerprint: fingerprint("merge-a")
        )
        let itemB = MediaItem(
            id: UUID(uuidString: "CCCC0000-0000-0000-0000-000000000002")!,
            title: "备份条目乙",
            relativePath: fileB,
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 10,
            fingerprint: fingerprint("merge-b")
        )
        backupEnv.context.insert(itemA)
        backupEnv.context.insert(itemB)
        let backupPlaylist = Playlist(name: "共享列表", sortOrder: 0)
        backupEnv.context.insert(backupPlaylist)
        backupEnv.context.insert(PlaylistEntry(
            playlistID: backupPlaylist.id, itemID: itemA.id, position: 0
        ))
        backupEnv.context.insert(PlaylistEntry(
            playlistID: backupPlaylist.id, itemID: itemB.id, position: 1
        ))
        let oldUpdatedAt = Date(timeIntervalSince1970: 1_600_000_000)
        backupEnv.context.insert(PlaybackState(
            itemID: itemA.id,
            position: 5,
            duration: 100,
            playCount: 1,
            updatedAt: oldUpdatedAt
        ))
        try backupEnv.context.save()

        let document = try backupService.snapshot(in: backupEnv.context)
        let data = try backupJSONEncoder().encode(document)
        let decoded = try backupJSONDecoder().decode(BackupDocument.self, from: data)

        // Target library already has: itemA by id, itemB's CONTENT by
        // fingerprint (different id), a same-name playlist, and NEWER progress.
        let target = try makeEnvironment()
        let targetService = BackupService(storage: target.storage)

        let existingA = MediaItem(
            id: itemA.id,
            title: "本地条目甲",
            relativePath: "Media/local-a.m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 99,
            fingerprint: nil
        )
        let existingBContent = MediaItem(
            id: UUID(uuidString: "CCCC0000-0000-0000-0000-000000000099")!,
            title: "本地条目乙（同内容）",
            relativePath: "Media/local-b.m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 10,
            fingerprint: fingerprint("merge-b")
        )
        target.context.insert(existingA)
        target.context.insert(existingBContent)

        let existingPlaylist = Playlist(name: "共享列表", sortOrder: 0)
        target.context.insert(existingPlaylist)
        target.context.insert(PlaylistEntry(
            playlistID: existingPlaylist.id, itemID: existingBContent.id, position: 0
        ))

        let newUpdatedAt = Date(timeIntervalSince1970: 1_900_000_000)
        target.context.insert(PlaybackState(
            itemID: itemA.id,
            position: 88,
            duration: 100,
            playCount: 7,
            updatedAt: newUpdatedAt
        ))
        try target.context.save()

        let result = try targetService.restore(decoded, into: target.context)

        // itemA matched by id, itemB's backup row matched its existing content
        // via fingerprint (kept the EXISTING id).
        XCTAssertEqual(result.itemsMatched, 2)
        XCTAssertEqual(result.itemsRestored, 0)
        XCTAssertEqual(result.playlistsMerged, 1)
        XCTAssertEqual(result.playlistsCreated, 0)
        // Only itemB's entry was missing locally.
        XCTAssertEqual(result.playlistEntriesAdded, 1)
        // Local progress (1_900_000_000) is newer than backup (1_600_000_000).
        XCTAssertEqual(result.progressUpdated, 0)
        XCTAssertEqual(result.skipped, 0)

        let items = try target.context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(items.count, 2, "no duplicates")
        XCTAssertEqual(items.first { $0.id == itemA.id }?.title, "本地条目甲")
        XCTAssertTrue(items.contains { $0.id == existingBContent.id })

        let playlists = try target.context.fetch(FetchDescriptor<Playlist>())
        XCTAssertEqual(playlists.count, 1)
        let playlistService = PlaylistService(context: target.context)
        XCTAssertEqual(
            playlistService.itemIDs(in: playlists[0]),
            [existingBContent.id, itemA.id],
            "existing entry keeps its position; the missing one is appended"
        )

        let states = try target.context.fetch(FetchDescriptor<PlaybackState>())
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.position ?? 0, 88, accuracy: 0.001)
        XCTAssertEqual(states.first?.playCount, 7)
    }

    func testRestoreOverwritesProgressOnlyWhenBackupIsNewer() throws {
        let backupEnv = try makeEnvironment()
        let backupService = BackupService(storage: backupEnv.storage)

        let fileA = "Media/\(UUID().uuidString).m4a"
        try stageMediaFile(fileA, content: "progress-a", in: backupEnv)
        let itemA = MediaItem(
            id: UUID(uuidString: "DDDD0000-0000-0000-0000-000000000001")!,
            title: "进度条目",
            relativePath: fileA,
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 10
        )
        backupEnv.context.insert(itemA)
        let backupUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        backupEnv.context.insert(PlaybackState(
            itemID: itemA.id,
            position: 30,
            duration: 100,
            playCount: 3,
            updatedAt: backupUpdatedAt
        ))
        try backupEnv.context.save()
        let document = try backupService.snapshot(in: backupEnv.context)
        let decoded = try backupJSONDecoder().decode(
            BackupDocument.self,
            from: try backupJSONEncoder().encode(document)
        )

        // Target progress is OLDER than the backup: the backup must win.
        let target1 = try makeEnvironment()
        target1.context.insert(MediaItem(
            id: itemA.id,
            title: "进度条目",
            relativePath: "Media/local.m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 10
        ))
        target1.context.insert(PlaybackState(
            itemID: itemA.id,
            position: 1,
            duration: 100,
            playCount: 0,
            updatedAt: Date(timeIntervalSince1970: 1_000_000_000)
        ))
        try target1.context.save()

        let result1 = try BackupService(storage: target1.storage)
            .restore(decoded, into: target1.context)
        XCTAssertEqual(result1.progressUpdated, 1)
        let state1 = try target1.context.fetch(FetchDescriptor<PlaybackState>()).first
        XCTAssertEqual(state1?.position ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(state1?.playCount, 3)

        // Target progress is NEWER than the backup: keep the local row.
        let target2 = try makeEnvironment()
        target2.context.insert(MediaItem(
            id: itemA.id,
            title: "进度条目",
            relativePath: "Media/local.m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 10
        ))
        target2.context.insert(PlaybackState(
            itemID: itemA.id,
            position: 99,
            duration: 100,
            playCount: 9,
            updatedAt: Date(timeIntervalSince1970: 1_950_000_000)
        ))
        try target2.context.save()

        let result2 = try BackupService(storage: target2.storage)
            .restore(decoded, into: target2.context)
        XCTAssertEqual(result2.progressUpdated, 0)
        let state2 = try target2.context.fetch(FetchDescriptor<PlaybackState>()).first
        XCTAssertEqual(state2?.position ?? 0, 99, accuracy: 0.001)
        XCTAssertEqual(state2?.playCount, 9)
    }

    func testRestoreMarksMissingMediaAndReconnectsCollection() throws {
        let backupEnv = try makeEnvironment()
        let backupService = BackupService(storage: backupEnv.storage)

        let collection = MediaCollection(name: "云端合集", nameKey: "云端合集", sortOrder: 0)
        backupEnv.context.insert(collection)
        let item = MediaItem(
            id: UUID(uuidString: "EEEE0000-0000-0000-0000-000000000001")!,
            title: "缺失媒体的条目",
            relativePath: "Media/gone-\(UUID().uuidString).m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 12345,
            collectionID: collection.id
        )
        backupEnv.context.insert(item)
        try backupEnv.context.save()

        let document = try backupService.snapshot(in: backupEnv.context)
        let decoded = try backupJSONDecoder().decode(
            BackupDocument.self,
            from: try backupJSONEncoder().encode(document)
        )

        let target = try makeEnvironment()
        let result = try BackupService(storage: target.storage)
            .restore(decoded, into: target.context)

        XCTAssertEqual(result.itemsRestored, 1)
        XCTAssertEqual(result.itemsMissingMedia, 1)
        let restored = try target.context.fetch(FetchDescriptor<MediaItem>()).first
        XCTAssertEqual(restored?.isMissing, true, "file does not exist in target")
        XCTAssertEqual(restored?.byteSize, 12345)
        XCTAssertEqual(restored?.collectionID, collection.id)
    }

    func testRepeatedRestoreIsIdempotent() throws {
        let backupEnv = try makeEnvironment()
        let backupService = BackupService(storage: backupEnv.storage)
        let fileA = "Media/\(UUID().uuidString).m4a"
        try stageMediaFile(fileA, content: "idem-a", in: backupEnv)
        let item = MediaItem(
            id: UUID(uuidString: "FFFF0000-0000-0000-0000-000000000001")!,
            title: "幂等条目",
            relativePath: fileA,
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 10
        )
        backupEnv.context.insert(item)
        let playlist = Playlist(name: "幂等列表", sortOrder: 0)
        backupEnv.context.insert(playlist)
        backupEnv.context.insert(PlaylistEntry(
            playlistID: playlist.id, itemID: item.id, position: 0
        ))
        try backupEnv.context.save()
        let decoded = try backupJSONDecoder().decode(
            BackupDocument.self,
            from: try backupJSONEncoder().encode(
                try backupService.snapshot(in: backupEnv.context)
            )
        )

        let target = try makeEnvironment()
        let targetService = BackupService(storage: target.storage)
        _ = try targetService.restore(decoded, into: target.context)
        let second = try targetService.restore(decoded, into: target.context)

        XCTAssertEqual(second.itemsRestored, 0)
        XCTAssertEqual(second.itemsMatched, 1)
        XCTAssertEqual(second.playlistsCreated, 0)
        XCTAssertEqual(second.playlistEntriesAdded, 0)
        XCTAssertEqual(try target.context.fetchCount(FetchDescriptor<MediaItem>()), 1)
        XCTAssertEqual(try target.context.fetchCount(FetchDescriptor<Playlist>()), 1)
        XCTAssertEqual(try target.context.fetchCount(FetchDescriptor<PlaylistEntry>()), 1)
    }

    // MARK: - Validation

    func testCorruptJSONThrowsLocalizedError() throws {
        XCTAssertThrowsError(try BackupService.decode(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? BackupError, .corruptJSON)
            XCTAssertEqual(
                (error as? BackupError)?.errorDescription,
                LocalPodLocalization.string(
                    "backup.error.corrupt",
                    locale: Locale(identifier: "en")
                ),
                "errorDescription resolves through the kit bundle"
            )
            XCTAssertEqual(
                LocalPodLocalization.string(
                    "backup.error.corrupt",
                    locale: Locale(identifier: "zh-Hans")
                ),
                "备份文件已损坏，或不是 LocalPod 备份。",
                "zh-Hans table carries the Chinese message"
            )
        }
        // Truncated but structurally JSON-like data must also fail cleanly.
        let document = BackupDocument()
        let data = try BackupService.encodedJSON(document)
        XCTAssertThrowsError(try BackupService.decode(data.prefix(data.count / 2))) { error in
            XCTAssertEqual(error as? BackupError, .corruptJSON)
        }
    }

    func testWrongSchemaVersionThrowsLocalizedError() throws {
        var document = BackupDocument()
        document.schemaVersion = 99
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)

        // decode() itself only reports corrupt payloads; the version check
        // lives in readDocument (I/O entry) and restore (logic entry).
        let decoded = try BackupService.decode(data)
        XCTAssertEqual(decoded.schemaVersion, 99)

        // readDocument validates the version after decoding.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-version-\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try BackupService.readDocument(from: url)) { error in
            XCTAssertEqual(error as? BackupError, .unsupportedVersion(found: 99))
            let message = (error as? BackupError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("99"), "message mentions the found version: \(message)")
        }

        // restore() defends against a programmatically-built document too.
        let env = try makeEnvironment()
        XCTAssertThrowsError(
            try BackupService(storage: env.storage).restore(document, into: env.context)
        ) { error in
            XCTAssertEqual(error as? BackupError, .unsupportedVersion(found: 99))
        }
    }

    func testReadFailedSurfacesForMissingFile() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-backup-\(UUID().uuidString).json")
        XCTAssertThrowsError(try BackupService.readDocument(from: missing)) { error in
            guard case BackupError.readFailed = error else {
                return XCTFail("expected readFailed, got \(error)")
            }
        }
    }

    func testTolerantDecodingFillsMissingSectionsAndIgnoresExtraFields() throws {
        // A minimal v1 document with only the required version field.
        let minimal = Data(#"{"schemaVersion": 1}"#.utf8)
        let document = try BackupService.decode(minimal)
        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertTrue(document.items.isEmpty)
        XCTAssertTrue(document.collections.isEmpty)
        XCTAssertTrue(document.playlists.isEmpty)
        XCTAssertTrue(document.playbackStates.isEmpty)
        XCTAssertNil(document.queue)
        XCTAssertNil(document.settings)

        // Unknown fields are ignored.
        let withExtra = Data(
            #"{"schemaVersion": 1, "futureField": {"nested": true}, "items": []}"#.utf8
        )
        XCTAssertNoThrow(try BackupService.decode(withExtra))
    }

    // MARK: - Export file

    func testExportWritesValidJSONFile() throws {
        let env = try makeEnvironment()
        let item = MediaItem(
            title: "导出条目",
            relativePath: "Media/export.m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 10
        )
        env.context.insert(item)
        try env.context.save()
        let document = try BackupService(storage: env.storage).snapshot(in: env.context)

        let url = try BackupService.exportURL(document)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(url.lastPathComponent.hasPrefix("LocalPod-backup-"))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".json"))
        let data = try Data(contentsOf: url)
        let roundTripped = try BackupService.readDocument(from: url)
        XCTAssertEqual(roundTripped.items.first?.id, item.id)
        XCTAssertEqual(roundTripped.items.count, document.items.count)
        XCTAssertEqual(roundTripped.schemaVersion, BackupDocument.currentSchemaVersion)
        XCTAssertTrue(data.count > 2, "exported payload is not empty")

        // ISO-8601 dates are human-checkable in the payload.
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(
            text.contains(#""exportedAt""#),
            "payload keeps the exportedAt field"
        )
        XCTAssertTrue(
            text.contains(#""schemaVersion""#) && text.contains("1"),
            "payload records schema version 1"
        )
    }

    func testDefaultFileNameFormat() {
        let date = Date(timeIntervalSince1970: 1_762_000_000) // fixed date
        let name = BackupService.defaultFileName(now: date)
        XCTAssertTrue(name.hasPrefix("LocalPod-backup-"))
        XCTAssertTrue(name.hasSuffix(".json"))
        XCTAssertEqual(
            name.dropFirst("LocalPod-backup-".count).dropLast(".json".count).count,
            10,
            "YYYY-MM-DD has ten characters"
        )
    }

    // MARK: - Settings

    func testSettingsRoundTripClampsInvalidValues() throws {
        let suiteName = "LocalPodBackupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeSettings(defaults: defaults)
        store.defaultRate = 2.0
        store.skipBackwardSeconds = 45

        let backupSettings = BackupSettings(store: store)
        let document = BackupDocument(settings: backupSettings)
        let decoded = try backupJSONDecoder().decode(
            BackupDocument.self,
            from: try backupJSONEncoder().encode(document)
        )
        XCTAssertEqual(decoded.settings?.defaultRate, 2.0)

        let other = makeSettings(defaults: defaults)
        other.defaultRate = 1.0
        decoded.settings?.apply(to: other)
        XCTAssertEqual(other.defaultRate, 2.0, accuracy: 0.001)
        XCTAssertEqual(other.skipBackwardSeconds, 45)

        // Out-of-range values are clamped exactly like AppSettingsStore reads.
        var bad = BackupSettings(
            defaultRate: 99,
            skipForwardSeconds: 5_000,
            skipBackwardSeconds: 0,
            resumeEnabled: true,
            autoPlayNext: true,
            signingReminderEnabled: true
        )
        bad.apply(to: other)
        XCTAssertEqual(other.defaultRate, PlaybackPolicy.clampedRate(99))
        XCTAssertEqual(other.skipForwardSeconds, 120, "skip values clamp to 5…120")
        XCTAssertEqual(
            other.skipBackwardSeconds,
            min(max(0, 5), 120),
            "0 is below the 5-second floor and clamps to it"
        )
    }
}

/// Plain ISO-8601 coder pair for round-trip fixtures, mirroring what the
/// service's own export/import I/O uses.
private func backupJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

private func backupJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}
