import SwiftData
import XCTest
@testable import LocalPodKit

@MainActor
final class QueueManagerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var queue: QueueManager!

    override func setUp() async throws {
        container = try LocalPodStore.makeContainer(inMemory: true)
        context = container.mainContext
        queue = QueueManager()
        queue.attach(context: context)
    }

    override func tearDown() async throws {
        queue = nil
        context = nil
        container = nil
    }

    func testPlayAllReplacesQueueAndPlayNextInsertAfterCurrent() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
        queue.setQueue(itemIDs: [a, b, c], current: b)
        XCTAssertEqual(queue.itemIDs, [a, b, c])
        XCTAssertEqual(queue.currentItemID, b)

        queue.insertNext(d)
        XCTAssertEqual(queue.itemIDs, [a, b, d, c], "play next must sit after the current item")

        queue.append(e)
        XCTAssertEqual(queue.itemIDs, [a, b, d, c, e], "enqueue must append at the tail")

        let f = UUID(), g = UUID()
        queue.setQueue(itemIDs: [f, g], current: g)
        XCTAssertEqual(queue.itemIDs, [f, g], "playing an item/play-all replaces the queue")
        XCTAssertEqual(queue.currentItemID, g)
    }

    func testAdvanceSequentialRepeatModes() {
        let a = UUID(), b = UUID(), c = UUID()
        queue.setQueue(itemIDs: [a, b, c], current: a)

        XCTAssertEqual(queue.advance(), b)
        XCTAssertEqual(queue.advance(), c)
        XCTAssertNil(queue.advance(), "repeat off must stop at the tail")
        XCTAssertEqual(queue.currentItemID, c)

        queue.setRepeatMode(.all)
        XCTAssertEqual(queue.advance(), a, "repeat all must wrap")

        queue.setRepeatMode(.one)
        XCTAssertEqual(queue.advance(), a, "repeat one must stay on the current item")
    }

    func testPreviousWalksBackAndOnlyWrapsWithRepeatAll() {
        let a = UUID(), b = UUID(), c = UUID()
        queue.setQueue(itemIDs: [a, b, c], current: b)
        XCTAssertEqual(queue.previous(), a)
        XCTAssertNil(queue.previous())
        queue.setRepeatMode(.all)
        XCTAssertEqual(queue.previous(), c)
    }

    func testQueueStateRestoresAfterRestart() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        queue.setQueue(itemIDs: [a, b, c, d], current: b, shuffle: false, repeatMode: .all)
        queue.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        let expectedOrder = queue.itemIDs
        queue.setShuffle(true)
        let expectedShuffle = queue.playOrder
        queue.setRepeatMode(.one)

        let restored = QueueManager()
        restored.attach(context: context)
        XCTAssertEqual(restored.itemIDs, expectedOrder)
        XCTAssertEqual(restored.currentItemID, b)
        XCTAssertTrue(restored.shuffleEnabled)
        XCTAssertEqual(restored.playOrder, expectedShuffle)
        XCTAssertEqual(restored.repeatMode, .one)
    }

    func testShuffleOrderIsPermutationAndAdvancesWithoutImmediateRepeat() {
        let ids = (0..<6).map { _ in UUID() }
        queue.setQueue(itemIDs: ids, current: ids[0])
        queue.setShuffle(true)

        XCTAssertEqual(queue.playOrder.count, ids.count)
        XCTAssertEqual(Set(queue.playOrder), Set(ids))
        XCTAssertEqual(queue.playOrder.first, ids[0], "shuffle starts from the current item")

        guard let next = queue.advance() else {
            return XCTFail("shuffle should advance")
        }
        XCTAssertNotEqual(next, ids[0])
        XCTAssertTrue(ids.contains(next))
    }

    func testRemovingCurrentAdvancesAndLastRemovalEmptiesQueue() {
        let a = UUID(), b = UUID(), c = UUID()
        queue.setQueue(itemIDs: [a, b, c], current: b)
        XCTAssertEqual(queue.removeCurrentAndAdvance(), c)

        queue.setQueue(itemIDs: [a], current: a)
        XCTAssertNil(queue.removeCurrentAndAdvance())
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.currentItemID)
    }

    func testRemovingNonCurrentEntryKeepsPlaybackTarget() {
        let a = UUID(), b = UUID(), c = UUID()
        queue.setQueue(itemIDs: [a, b, c], current: a)
        let entryID = queue.entries[2].id
        XCTAssertFalse(queue.removeEntry(id: entryID))
        XCTAssertEqual(queue.itemIDs, [a, b])
        XCTAssertEqual(queue.currentItemID, a)
    }

    func testDuplicateAddMovesExistingEntryInsteadOfDuplicating() {
        let a = UUID(), b = UUID()
        queue.setQueue(itemIDs: [a, b], current: a)
        queue.append(a)
        XCTAssertEqual(queue.itemIDs, [b, a])
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.currentItemID, a)
    }

    func testDragMovePersistsAcrossManager() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        queue.setQueue(itemIDs: [a, b, c, d], current: a)
        queue.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(queue.itemIDs, [d, a, b, c])

        let restored = QueueManager()
        restored.attach(context: context)
        XCTAssertEqual(restored.itemIDs, [d, a, b, c])
    }

    func testClearRemovesEntriesAndState() {
        let a = UUID(), b = UUID()
        queue.setQueue(itemIDs: [a, b], current: a, repeatMode: .all)
        queue.clear()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.currentItemID)
        XCTAssertEqual(queue.repeatMode, .all, "repeat preference survives clearing the queue")

        let restored = QueueManager()
        restored.attach(context: context)
        XCTAssertTrue(restored.isEmpty)
        XCTAssertNil(restored.currentItemID)
    }
}
