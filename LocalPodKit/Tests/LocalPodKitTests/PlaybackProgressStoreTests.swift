import Foundation
import SwiftData
import XCTest
@testable import LocalPodKit

@MainActor
final class PlaybackProgressStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var store: PlaybackProgressStore!

    override func setUpWithError() throws {
        container = try LocalPodStore.makeContainer(inMemory: true)
        store = PlaybackProgressStore(context: container.mainContext)
    }

    override func tearDownWithError() throws {
        store = nil
        container = nil
    }

    private func stateCount() throws -> Int {
        try container.mainContext.fetchCount(FetchDescriptor<PlaybackState>())
    }

    func testNewItemHasNoProgressAndDoesNotResume() throws {
        let id = UUID()
        XCTAssertNil(try store.state(for: id))
        XCTAssertEqual(try store.resumePosition(for: id, fallbackDuration: 300), 0)
    }

    func testRecordPlayStartCountsPlaysAndStampsTime() throws {
        let id = UUID()
        let before = Date()
        let state = try store.recordPlayStart(itemID: id, duration: 300)
        XCTAssertEqual(state.playCount, 1)
        XCTAssertEqual(state.duration, 300)
        XCTAssertNotNil(state.lastPlayedAt)
        XCTAssertGreaterThanOrEqual(state.lastPlayedAt!, before)
        XCTAssertEqual(try stateCount(), 1)

        let second = try store.recordPlayStart(itemID: id, duration: 300)
        XCTAssertEqual(second.playCount, 2)
        XCTAssertEqual(try stateCount(), 1)
    }

    func testSaveAndResumeRoundTrip() throws {
        let id = UUID()
        try store.recordPlayStart(itemID: id, duration: 300)
        try store.save(itemID: id, position: 123.5, duration: 300, isFinished: false)

        XCTAssertEqual(try store.resumePosition(for: id), 123.5)
        XCTAssertEqual(try stateCount(), 1)
    }

    func testFinishedItemDoesNotResumeAndReplayStartsOver() throws {
        let id = UUID()
        try store.recordPlayStart(itemID: id, duration: 300)
        try store.markFinished(itemID: id, duration: 300)

        let state = try XCTUnwrap(store.state(for: id))
        XCTAssertTrue(state.isFinished)
        XCTAssertEqual(state.position, 300)
        XCTAssertEqual(try store.resumePosition(for: id), 0)

        let replayed = try store.recordPlayStart(itemID: id, duration: 300)
        XCTAssertFalse(replayed.isFinished)
        XCTAssertEqual(replayed.position, 0)
        XCTAssertEqual(replayed.playCount, 2)
    }

    func testPositionIsClampedToDuration() throws {
        let id = UUID()
        let state = try store.save(itemID: id, position: 999, duration: 120, isFinished: false)
        XCTAssertEqual(state.position, 120)

        let negative = try store.save(itemID: id, position: -10, duration: 120, isFinished: false)
        XCTAssertEqual(negative.position, 0)
    }

    func testInvalidValuesAreIgnored() throws {
        let id = UUID()
        try store.recordPlayStart(itemID: id, duration: 300)
        let saved = try store.save(
            itemID: id,
            position: .nan,
            duration: .infinity,
            isFinished: false
        )
        XCTAssertEqual(saved.position, 0)
        XCTAssertEqual(saved.duration, 300)
    }

    func testFallbackDurationIsUsedWhenStateHasNone() throws {
        let id = UUID()
        let state = try store.save(itemID: id, position: 90, duration: 0, isFinished: false)
        XCTAssertEqual(state.duration, 0)
        // The saved row has no duration, so resume needs the library hint.
        XCTAssertEqual(try store.resumePosition(for: id, fallbackDuration: 300), 90)
        XCTAssertEqual(try store.resumePosition(for: id), 0)
    }

    func testDeleteState() throws {
        let id = UUID()
        try store.recordPlayStart(itemID: id, duration: 60)
        XCTAssertEqual(try stateCount(), 1)
        try store.deleteState(for: id)
        XCTAssertEqual(try stateCount(), 0)
        XCTAssertNil(try store.state(for: id))
    }

    func testProgressRowsAreIndependentPerItem() throws {
        let first = UUID()
        let second = UUID()
        try store.save(itemID: first, position: 10, duration: 300, isFinished: false)
        try store.save(itemID: second, position: 20, duration: 300, isFinished: false)

        XCTAssertEqual(try store.resumePosition(for: first), 10)
        XCTAssertEqual(try store.resumePosition(for: second), 20)
        XCTAssertEqual(try stateCount(), 2)
    }

    // MARK: - Status switching (item 4)

    func testStatusStartsNotStarted() throws {
        XCTAssertEqual(try store.status(for: UUID()), .notStarted)
    }

    func testStatusInProgressAfterPlayStart() throws {
        let id = UUID()
        try store.recordPlayStart(itemID: id, duration: 300)
        XCTAssertEqual(try store.status(for: id), .inProgress)
    }

    func testMarkUnfinishedResetsEndPosition() throws {
        let id = UUID()
        try store.recordPlayStart(itemID: id, duration: 300)
        try store.markFinished(itemID: id, duration: 300)
        XCTAssertEqual(try store.status(for: id), .finished)

        try store.markUnfinished(itemID: id)
        XCTAssertEqual(try store.status(for: id), .inProgress)
        // A position parked at the end is rewound so the next write cannot
        // immediately re-finish the item.
        XCTAssertEqual(try store.state(for: id)?.position, 0)
        XCTAssertEqual(try store.resumePosition(for: id), 0)
    }

    func testMarkUnfinishedKeepsMidPosition() throws {
        let id = UUID()
        try store.save(itemID: id, position: 120, duration: 300, isFinished: true)

        try store.markUnfinished(itemID: id)
        XCTAssertEqual(try store.state(for: id)?.position, 120)
    }

    func testResetProgressClearsContinueStripState() throws {
        let id = UUID()
        try store.recordPlayStart(itemID: id, duration: 300)
        try store.save(itemID: id, position: 42, duration: 300, isFinished: false)

        try store.resetProgress(itemID: id)
        XCTAssertEqual(try store.status(for: id), .notStarted)
        XCTAssertEqual(try store.state(for: id)?.position, 0)
        XCTAssertEqual(try store.state(for: id)?.playCount, 0)
        XCTAssertNil(try store.state(for: id)?.lastPlayedAt)
    }

    func testResetProgressOnFinishedItemAllowsReplayFromStart() throws {
        let id = UUID()
        try store.recordPlayStart(itemID: id, duration: 300)
        try store.markFinished(itemID: id, duration: 300)
        try store.resetProgress(itemID: id)

        XCTAssertEqual(try store.status(for: id), .notStarted)
        XCTAssertEqual(try store.resumePosition(for: id), 0)
    }

    func testStatusDisplayNamesAreLocalized() {
        for status in PlaybackStatus.allCases {
            let zh = status.displayName(locale: Locale(identifier: "zh-Hans"))
            let en = status.displayName(locale: Locale(identifier: "en"))
            XCTAssertFalse(zh.contains("playback.status"), "\(status) zh")
            XCTAssertFalse(en.contains("playback.status"), "\(status) en")
            XCTAssertNotEqual(zh, en, "\(status) should differ between zh and en")
        }
    }
}
