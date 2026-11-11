import Foundation
import SwiftData
import XCTest
@testable import LocalPodKit

@MainActor
final class TrashTests: XCTestCase {
    @MainActor
    private struct Environment {
        let root: TemporaryDirectory
        let storage: MediaStorage
        let library: LibraryService
        let trash: TrashService
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
            library: LibraryService(storage: storage),
            trash: TrashService(storage: storage),
            container: try LocalPodStore.makeContainer(inMemory: true)
        )
    }

    /// Inserts an item with a real media file under `Media/` and returns it.
    private func makeItem(
        _ env: Environment,
        title: String,
        withFile: Bool = true
    ) throws -> MediaItem {
        let itemID = UUID()
        let relativePath = "Media/\(itemID.uuidString).m4a"
        if withFile {
            let mediaRoot = try env.storage.mediaRootURL()
            try Data(repeating: 0x41, count: 128).write(
                to: mediaRoot.appendingPathComponent("\(itemID.uuidString).m4a")
            )
        }
        let item = MediaItem(
            id: itemID,
            title: title,
            sortTitle: title,
            originalFileName: "\(itemID.uuidString).m4a",
            relativePath: relativePath,
            relativeFolderPath: "",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 128,
            durationSeconds: 12.5,
            folderName: "回收站测试",
            fingerprint: nil,
            artworkKey: nil
        )
        env.context.insert(item)
        try env.context.save()
        return item
    }

    // MARK: - Move to trash

    func testMoveToTrashRemovesRowStagesFileAndSnapshotsMembership() throws {
        let env = try makeEnvironment()
        let item = try makeItem(env, title: "条目一")
        let playlist = Playlist(name: "列表")
        env.context.insert(playlist)
        env.context.insert(PlaylistEntry(
            playlistID: playlist.id,
            itemID: item.id,
            position: 2
        ))
        env.context.insert(PlaybackState(itemID: item.id, position: 4, duration: 12.5))
        env.context.insert(QueueEntry(itemID: item.id, position: 0))
        try env.context.save()

        let addedAt = item.addedAt
        let result = try env.trash.moveToTrash(item, in: env.context)

        XCTAssertEqual(result.title, "条目一")
        XCTAssertTrue(result.stagedMediaFile)
        XCTAssertEqual(result.trashedPlaylistEntryCount, 1)

        // The item disappears from every MediaItem query.
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaItem>()), 0)
        // Queue must not reference an invisible item; playback state survives.
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<QueueEntry>()), 0)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<PlaylistEntry>()), 0)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<PlaybackState>()), 1)

        // Media file moved into the trash staging directory.
        let rows = try env.context.fetch(FetchDescriptor<TrashItem>())
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.itemID, item.id)
        XCTAssertEqual(row.title, "条目一")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try env.storage.trashItemURL(itemID: item.id)
                    .appendingPathComponent("\(item.id.uuidString).m4a").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: try env.storage.url(forRelativePath: "Media/\(item.id.uuidString).m4a").path
            )
        )

        // Snapshot round-trips every MediaItem field.
        let snapshot = try TrashService.decodeSnapshot(from: row)
        XCTAssertEqual(snapshot.id, item.id)
        XCTAssertEqual(snapshot.title, "条目一")
        XCTAssertEqual(snapshot.sortTitle, item.sortTitle)
        XCTAssertEqual(snapshot.originalFileName, item.originalFileName)
        XCTAssertEqual(snapshot.relativePath, item.relativePath)
        XCTAssertEqual(snapshot.kindRaw, MediaKind.audio.rawValue)
        XCTAssertEqual(snapshot.fileExtension, "m4a")
        XCTAssertEqual(snapshot.byteSize, 128)
        XCTAssertEqual(snapshot.durationSeconds, 12.5)
        XCTAssertEqual(snapshot.addedAt, addedAt)
        XCTAssertEqual(snapshot.folderName, "回收站测试")
        XCTAssertEqual(snapshot.sourceRaw, MediaSource.imported.rawValue)
        XCTAssertEqual(snapshot.playlistEntries.map(\.playlistID), [playlist.id])
        XCTAssertEqual(snapshot.playlistEntries.map(\.position), [2])
        // Expiry = deletedAt + retention.
        XCTAssertEqual(
            row.expiresAt.timeIntervalSince(row.deletedAt),
            TrashService.retentionInterval,
            accuracy: 1
        )
    }

    func testMoveToTrashWithoutMediaFileStillCreatesRow() throws {
        let env = try makeEnvironment()
        let item = try makeItem(env, title: "无文件", withFile: false)

        let result = try env.trash.moveToTrash(item, in: env.context)

        XCTAssertFalse(result.stagedMediaFile)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<TrashItem>()), 1)
    }

    // MARK: - Restore

    func testRestoreRecreatesItemFileAndPlaylistMembership() throws {
        let env = try makeEnvironment()
        let item = try makeItem(env, title: "恢复目标")
        let playlist = Playlist(name: "列表")
        env.context.insert(playlist)
        env.context.insert(PlaylistEntry(
            playlistID: playlist.id,
            itemID: item.id,
            position: 3
        ))
        env.context.insert(PlaybackState(itemID: item.id, position: 7, duration: 12.5))
        try env.context.save()
        let addedAt = item.addedAt

        _ = try env.trash.moveToTrash(item, in: env.context)
        // More entries joined the playlist while the item was away; restore
        // must not disturb their positions beyond normalizing gaps.
        let survivor = UUID()
        env.context.insert(PlaylistEntry(
            playlistID: playlist.id,
            itemID: survivor,
            position: 0
        ))
        try env.context.save()

        let playlistID = playlist.id
        let row = try XCTUnwrap(try env.context.fetch(FetchDescriptor<TrashItem>()).first)
        let result = try env.trash.restore(row, in: env.context)

        XCTAssertTrue(result.mediaFileRestored)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: try env.storage.url(forRelativePath: "Media/\(item.id.uuidString).m4a").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: try env.storage.trashItemURL(itemID: item.id).path
        ))
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<TrashItem>()), 0)

        let restored = try XCTUnwrap(try env.context.fetch(FetchDescriptor<MediaItem>()).first)
        XCTAssertEqual(restored.id, item.id)
        XCTAssertEqual(restored.title, "恢复目标")
        XCTAssertEqual(restored.addedAt, addedAt, "restore keeps the original addedAt")
        XCTAssertFalse(restored.isMissing)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<PlaybackState>()), 1)
        let entryPositions = try env.context.fetch(FetchDescriptor<PlaylistEntry>(
            predicate: #Predicate { $0.playlistID == playlistID },
            sortBy: [SortDescriptor(\.position)]
        ))
        XCTAssertEqual(Set(entryPositions.map(\.itemID)), [item.id, survivor])
        XCTAssertEqual(
            entryPositions.map(\.position),
            [0, 1],
            "positions must stay dense after restore"
        )
    }

    func testRestoreWithMissingFileMarksItemMissing() throws {
        let env = try makeEnvironment()
        let item = try makeItem(env, title: "文件已丢", withFile: true)

        _ = try env.trash.moveToTrash(item, in: env.context)
        // The staged file disappears (user cleared the app support dir, etc.).
        try FileManager.default.removeItem(at: env.storage.trashItemURL(itemID: item.id))

        let row = try XCTUnwrap(try env.context.fetch(FetchDescriptor<TrashItem>()).first)
        let result = try env.trash.restore(row, in: env.context)

        XCTAssertFalse(result.mediaFileRestored)
        let restored = try XCTUnwrap(try env.context.fetch(FetchDescriptor<MediaItem>()).first)
        XCTAssertEqual(restored.id, item.id)
        XCTAssertTrue(restored.isMissing, "existing missing-handling flow takes over")
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<TrashItem>()), 0)
    }

    func testRestoreKeepsPlaylistMembershipWhenPlaylistWasDeleted() throws {
        let env = try makeEnvironment()
        let item = try makeItem(env, title: "列表已删")
        let playlist = Playlist(name: "将删除的列表")
        env.context.insert(playlist)
        env.context.insert(PlaylistEntry(
            playlistID: playlist.id,
            itemID: item.id,
            position: 0
        ))
        try env.context.save()

        _ = try env.trash.moveToTrash(item, in: env.context)
        env.context.delete(playlist)
        try env.context.save()

        let row = try XCTUnwrap(try env.context.fetch(FetchDescriptor<TrashItem>()).first)
        let result = try env.trash.restore(row, in: env.context)

        XCTAssertEqual(result.restoredPlaylistEntryCount, 0)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<PlaylistEntry>()), 0)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaItem>()), 1)
    }

    // MARK: - Purge

    func testPurgeRemovesFileArtworkPlaybackAndQueueRows() throws {
        let env = try makeEnvironment()
        let itemID = UUID()
        let relativePath = "Media/\(itemID.uuidString).m4a"
        let mediaRoot = try env.storage.mediaRootURL()
        try Data(repeating: 0x41, count: 128).write(
            to: mediaRoot.appendingPathComponent("\(itemID.uuidString).m4a")
        )
        let artworkKey = "\(itemID.uuidString).jpg"
        try Data(repeating: 0xCD, count: 32).write(
            to: try env.storage.artworkURL(forKey: artworkKey)
        )
        let item = MediaItem(
            id: itemID,
            title: "清除目标",
            sortTitle: "清除目标",
            originalFileName: "\(itemID.uuidString).m4a",
            relativePath: relativePath,
            relativeFolderPath: "",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 128,
            durationSeconds: 12.5,
            folderName: "回收站测试",
            fingerprint: nil,
            artworkKey: artworkKey
        )
        env.context.insert(item)
        env.context.insert(PlaybackState(itemID: itemID, position: 9, duration: 12.5))
        env.context.insert(QueueEntry(itemID: itemID, position: 0))
        try env.context.save()

        _ = try env.trash.moveToTrash(item, in: env.context)
        let row = try XCTUnwrap(try env.context.fetch(FetchDescriptor<TrashItem>()).first)
        let purged = try env.trash.purge(row, in: env.context)
        XCTAssertEqual(purged, 1)

        // No orphans anywhere.
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<TrashItem>()), 0)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaItem>()), 0)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<PlaybackState>()), 0)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<QueueEntry>()), 0)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: try env.storage.trashItemURL(itemID: itemID).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: try env.storage.url(forRelativePath: relativePath).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: try env.storage.artworkURL(forKey: artworkKey).path
        ))
    }

    func testEmptyTrashPurgesEverything() throws {
        let env = try makeEnvironment()
        let first = try makeItem(env, title: "清空一")
        let second = try makeItem(env, title: "清空二")
        _ = try env.trash.moveToTrash(first, in: env.context)
        _ = try env.trash.moveToTrash(second, in: env.context)

        let result = try env.trash.emptyTrash(in: env.context)

        XCTAssertEqual(result.purgedCount, 2)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<TrashItem>()), 0)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<MediaItem>()), 0)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                atPath: try env.storage.trashRootURL().path
            ).count,
            0
        )
    }

    func testPurgeExpiredRemovesOnlyExpiredRows() throws {
        let env = try makeEnvironment()
        let expired = try makeItem(env, title: "已过期")
        let fresh = try makeItem(env, title: "未过期")
        _ = try env.trash.moveToTrash(expired, in: env.context)
        _ = try env.trash.moveToTrash(fresh, in: env.context)

        let rows = try env.context.fetch(FetchDescriptor<TrashItem>())
        for row in rows {
            if row.title == "已过期" {
                row.expiresAt = Date().addingTimeInterval(-60)
            }
        }
        try env.context.save()

        let result = try env.trash.purgeExpired(in: env.context)

        XCTAssertEqual(result.purgedCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        let remaining = try env.context.fetch(FetchDescriptor<TrashItem>())
        XCTAssertEqual(remaining.map(\.title), ["未过期"])
        // The purged row's staged file is gone; the fresh one is still there.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: try env.storage.trashItemURL(itemID: expired.id).path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: try env.storage.trashItemURL(itemID: fresh.id).path
        ))
    }

    // MARK: - Reconcile interaction

    func testReconcilePurgesExpiredAndNeverTouchesTrashStaging() throws {
        let env = try makeEnvironment()
        let live = try makeItem(env, title: "在库条目")
        let expired = try makeItem(env, title: "过期回收")
        _ = try env.trash.moveToTrash(expired, in: env.context)

        let rows = try env.context.fetch(FetchDescriptor<TrashItem>())
        rows.first?.expiresAt = Date().addingTimeInterval(-60)
        try env.context.save()
        XCTAssertFalse(live.isMissing)

        let summary = try env.library.reconcile(in: env.context)

        XCTAssertEqual(summary.expiredTrashPurged, 1)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<TrashItem>()), 0)
        // The live item's file was never touched; no missing marking.
        XCTAssertEqual(summary.missingMarked, 0)
        XCTAssertFalse(live.isMissing)
        // Other trash staging is untouched: the fresh trash root only ever
        // held the expired item, which purge removed.
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                atPath: try env.storage.trashRootURL().path
            ).count,
            0
        )
    }

    func testReconcileKeepsNonExpiredTrashStagingAlone() throws {
        let env = try makeEnvironment()
        let live = try makeItem(env, title: "在库条目")
        let trashed = try makeItem(env, title: "回收中")
        _ = try env.trash.moveToTrash(trashed, in: env.context)

        let summary = try env.library.reconcile(in: env.context)

        XCTAssertEqual(summary.expiredTrashPurged, 0)
        XCTAssertEqual(summary.missingMarked, 0)
        XCTAssertEqual(summary.orphanMediaFilesRemoved, 0)
        XCTAssertFalse(live.isMissing)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<TrashItem>()), 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: try env.storage.trashItemURL(itemID: trashed.id)
                .appendingPathComponent("\(trashed.id.uuidString).m4a").path
        ))
    }

    // MARK: - V5 → V6 migration

    func testV5StoreMigratesToV6AndAddsTrashItem() throws {
        let root = try TemporaryDirectory()
        let storeURL = root.url.appendingPathComponent("LocalPod.store")

        try makeV5Store(at: storeURL)
        let container = try openV6Store(at: storeURL)
        let context = container.mainContext

        // Pre-existing data survived the lightweight migration.
        let items = try context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "V5 item")
        let states = try context.fetch(FetchDescriptor<PlaybackState>())
        XCTAssertEqual(states.count, 1)

        // The new entity is usable right after migration.
        context.insert(TrashItem(
            itemID: items[0].id,
            title: "迁移后的回收条目",
            snapshotJSON: Data("{}".utf8),
            deletedAt: Date(),
            expiresAt: Date().addingTimeInterval(60)
        ))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrashItem>()), 1)
    }

    private func makeV5Store(at url: URL) throws {
        let schema = Schema(versionedSchema: LocalPodSchemaV5.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
        let context = container.mainContext
        let item = LocalPodSchemaV2.MediaItem(
            title: "V5 item",
            relativePath: "Media/v5.m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 888,
            durationSeconds: 60
        )
        context.insert(item)
        context.insert(LocalPodSchemaV3.PlaybackState(
            itemID: item.id,
            position: 6,
            duration: 60
        ))
        try context.save()
    }

    private func openV6Store(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LocalPodSchemaV6.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: LocalPodMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
