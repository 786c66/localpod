import SwiftData
import XCTest
@testable import LocalPodKit

@MainActor
final class PlaylistServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: PlaylistService!

    override func setUp() async throws {
        container = try LocalPodStore.makeContainer(inMemory: true)
        context = container.mainContext
        service = PlaylistService(context: context)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
    }

    func testCreateRenameAndSortOrder() {
        XCTAssertNil(service.create(name: "   "), "blank names are rejected")
        let first = try! XCTUnwrap(service.create(name: " 通勤 "))
        let second = try! XCTUnwrap(service.create(name: "睡前"))
        XCTAssertEqual(first.name, "通勤")
        XCTAssertEqual(second.name, "睡前")
        XCTAssertEqual(first.sortOrder, 0)
        XCTAssertEqual(second.sortOrder, 1)
        XCTAssertEqual(service.allPlaylists().map(\.name), ["通勤", "睡前"])

        XCTAssertTrue(service.rename(first, to: "开车"))
        XCTAssertEqual(first.name, "开车")
        XCTAssertFalse(service.rename(second, to: "  "))
    }

    func testAddDeduplicatesAndRemoveNormalizesPositions() {
        let playlist = try! XCTUnwrap(service.create(name: "列表"))
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertTrue(service.add(itemID: a, to: playlist))
        XCTAssertTrue(service.add(itemID: b, to: playlist))
        XCTAssertTrue(service.add(itemID: c, to: playlist))
        XCTAssertFalse(service.add(itemID: b, to: playlist), "same item is not added twice")
        XCTAssertEqual(service.itemIDs(in: playlist), [a, b, c])

        XCTAssertTrue(service.remove(itemID: b, from: playlist))
        XCTAssertEqual(service.itemIDs(in: playlist), [a, c])
        XCTAssertEqual(service.entries(in: playlist).map(\.position), [0, 1])
    }

    func testMovePersistsAcrossServiceInstances() {
        let playlist = try! XCTUnwrap(service.create(name: "排序"))
        let ids = (0..<4).map { _ in UUID() }
        service.add(itemIDs: ids, to: playlist)

        service.move(in: playlist, fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(service.itemIDs(in: playlist), [ids[3], ids[0], ids[1], ids[2]])

        let another = PlaylistService(context: context)
        XCTAssertEqual(
            another.itemIDs(in: playlist),
            [ids[3], ids[0], ids[1], ids[2]],
            "reorder is persisted immediately"
        )
    }

    func testRemoveEntryAndDeletePlaylist() {
        let keep = try! XCTUnwrap(service.create(name: "保留"))
        let remove = try! XCTUnwrap(service.create(name: "删除"))
        let a = UUID(), b = UUID()
        service.add(itemID: a, to: keep)
        service.add(itemID: b, to: keep)
        service.add(itemID: a, to: remove)

        let entry = try! XCTUnwrap(service.entries(in: keep).first)
        XCTAssertTrue(service.removeEntry(id: entry.id))
        XCTAssertEqual(service.itemIDs(in: keep), [b])

        service.delete(remove)
        XCTAssertEqual(service.allPlaylists().map(\.name), ["保留"])
        XCTAssertEqual(service.itemIDs(in: keep), [b])
        let allEntries = (try? context.fetch(FetchDescriptor<PlaylistEntry>())) ?? []
        XCTAssertEqual(allEntries.count, 1, "deleting a playlist must delete its entries")
    }

    func testRemoveAllEntriesForDeletedLibraryItem() {
        let first = try! XCTUnwrap(service.create(name: "一"))
        let second = try! XCTUnwrap(service.create(name: "二"))
        let itemID = UUID()
        service.add(itemID: itemID, to: first)
        service.add(itemID: itemID, to: second)
        service.add(itemID: UUID(), to: second)

        service.removeAllEntries(forItemID: itemID)
        XCTAssertTrue(service.itemIDs(in: first).isEmpty)
        XCTAssertEqual(service.itemIDs(in: second).count, 1)
    }

    func testLibraryDeleteTrashesItemAndRestoresPlaylistMembership() throws {
        let itemID = UUID()
        let item = MediaItem(
            id: itemID,
            title: "删除目标",
            relativePath: "Media/missing.m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 100
        )
        context.insert(item)
        context.insert(PlaybackState(itemID: itemID, position: 3, duration: 10))
        context.insert(QueueEntry(itemID: itemID, position: 0))
        let playlist = try XCTUnwrap(service.create(name: "级联"))
        service.add(itemID: itemID, to: playlist)
        try context.save()

        _ = try LibraryService().delete(item, in: context)

        // Trash: the item row is gone, queue rows are dropped, playlist
        // entries are removed (membership lives in the snapshot until
        // restore), and playback state is kept so restore reconnects by id.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MediaItem>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QueueEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlaybackState>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrashItem>()), 1)
        XCTAssertEqual(service.itemIDs(in: playlist), [])

        // Restore puts the item and its playlist entry back.
        let trashRow = try XCTUnwrap(
            try context.fetch(FetchDescriptor<TrashItem>()).first
        )
        _ = try TrashService().restore(trashRow, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MediaItem>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrashItem>()), 0)
        XCTAssertEqual(service.itemIDs(in: playlist), [itemID])
        let restoredState = try XCTUnwrap(
            try context.fetch(FetchDescriptor<PlaybackState>()).first
        )
        XCTAssertEqual(restoredState.position, 3)
    }

    func testLibraryDeleteHardCascadesQueuePlaylistAndProgressRows() throws {
        let itemID = UUID()
        let item = MediaItem(
            id: itemID,
            title: "删除目标",
            relativePath: "Media/missing.m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 100
        )
        context.insert(item)
        context.insert(PlaybackState(itemID: itemID, position: 3, duration: 10))
        context.insert(QueueEntry(itemID: itemID, position: 0))
        let playlist = try XCTUnwrap(service.create(name: "级联"))
        service.add(itemID: itemID, to: playlist)
        try context.save()

        _ = try LibraryService().deleteHard(item, in: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MediaItem>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlaybackState>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QueueEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlaylistEntry>()), 0)
    }
}
