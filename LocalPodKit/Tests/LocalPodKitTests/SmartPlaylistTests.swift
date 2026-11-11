import Foundation
import XCTest
@testable import LocalPodKit

final class SmartPlaylistTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private var collectionA: UUID { id(0xA0) }
    private var collectionB: UUID { id(0xB0) }

    // MARK: - Helpers

    /// Stable UUIDs whose string form sorts in numeric order, so tie-break
    /// expectations are easy to read.
    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!
    }

    private func days(_ count: Double) -> TimeInterval {
        count * 24 * 60 * 60
    }

    private func makePlayback(
        position: Double = 60,
        duration: Double = 600,
        isFinished: Bool = false,
        playCount: Int = 1,
        lastPlayedAt: Date? = nil
    ) -> SmartPlaylistPlayback {
        SmartPlaylistPlayback(
            position: position,
            duration: duration,
            isFinished: isFinished,
            playCount: playCount,
            lastPlayedAt: lastPlayedAt
        )
    }

    private func makeEntry(
        _ identifier: UUID,
        addedAt: Date? = nil,
        collectionID: UUID? = nil,
        isMissing: Bool = false,
        playback: SmartPlaylistPlayback? = nil
    ) -> SmartPlaylistEntry {
        SmartPlaylistEntry(
            id: identifier,
            addedAt: addedAt ?? now,
            collectionID: collectionID,
            isMissing: isMissing,
            playback: playback
        )
    }

    private func assertCountsMatchEntries(
        _ entries: [SmartPlaylistEntry],
        collectionID: UUID? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let counts = SmartPlaylistEngine.counts(
            entries,
            collectionID: collectionID,
            now: now
        )
        for kind in SmartPlaylistKind.allCases {
            let expected = SmartPlaylistEngine.entries(
                entries,
                kind: kind,
                collectionID: collectionID,
                now: now
            ).count
            XCTAssertEqual(
                counts[kind],
                expected,
                "count does not match entries() for \(kind)",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Kind metadata

    func testKindMetadata() {
        XCTAssertEqual(
            SmartPlaylistKind.allCases,
            [.continueListening, .unfinished, .recentlyAdded, .finished]
        )

        for kind in SmartPlaylistKind.allCases {
            XCTAssertEqual(kind.id, kind.rawValue)
            XCTAssertFalse(kind.symbolName.isEmpty)
        }

        XCTAssertEqual(SmartPlaylistKind.continueListening.symbolName, "play.circle")
        XCTAssertEqual(SmartPlaylistKind.unfinished.symbolName, "clock")
        XCTAssertEqual(SmartPlaylistKind.recentlyAdded.symbolName, "sparkles")
        XCTAssertEqual(SmartPlaylistKind.finished.symbolName, "checkmark.circle")
        XCTAssertEqual(SmartPlaylistEngine.defaultRecentWindow, days(30))
    }

    // MARK: - Missing and collection filtering

    func testMissingEntriesAreExcludedFromEveryKind() {
        let missingUnfinished = makeEntry(
            id(1),
            isMissing: true,
            playback: makePlayback(position: 30, playCount: 2, lastPlayedAt: now)
        )
        let missingFinished = makeEntry(
            id(2),
            isMissing: true,
            playback: makePlayback(position: 30, isFinished: true, playCount: 2, lastPlayedAt: now)
        )
        let liveUnfinished = makeEntry(
            id(3),
            playback: makePlayback(position: 30, playCount: 2, lastPlayedAt: now)
        )
        let liveFinished = makeEntry(
            id(4),
            playback: makePlayback(position: 30, isFinished: true, playCount: 2, lastPlayedAt: now)
        )
        let entries = [missingUnfinished, missingFinished, liveUnfinished, liveFinished]

        for kind in SmartPlaylistKind.allCases {
            let result = SmartPlaylistEngine.entries(entries, kind: kind, now: now)
            XCTAssertFalse(
                result.contains { $0.id == missingUnfinished.id },
                "\(kind) included an in-progress missing entry"
            )
            XCTAssertFalse(
                result.contains { $0.id == missingFinished.id },
                "\(kind) included a finished missing entry"
            )
        }

        let counts = SmartPlaylistEngine.counts(entries, now: now)
        XCTAssertEqual(counts[.continueListening], 1)
        XCTAssertEqual(counts[.unfinished], 1)
        XCTAssertEqual(counts[.recentlyAdded], 2)
        XCTAssertEqual(counts[.finished], 1)
    }

    func testCollectionFilterAppliesToEveryKind() {
        let entries = [
            makeEntry(
                id(1),
                collectionID: collectionA,
                playback: makePlayback(position: 10, playCount: 1, lastPlayedAt: now)
            ),
            makeEntry(
                id(2),
                collectionID: collectionB,
                playback: makePlayback(position: 10, playCount: 1, lastPlayedAt: now)
            ),
            makeEntry(
                id(3),
                collectionID: nil,
                playback: makePlayback(position: 10, playCount: 1, lastPlayedAt: now)
            ),
            makeEntry(
                id(4),
                collectionID: collectionA,
                isMissing: true,
                playback: makePlayback(position: 10, playCount: 1, lastPlayedAt: now)
            ),
            makeEntry(
                id(5),
                collectionID: collectionA,
                playback: makePlayback(position: 10, isFinished: true, playCount: 1, lastPlayedAt: now)
            ),
            makeEntry(
                id(6),
                collectionID: collectionB,
                playback: makePlayback(position: 10, isFinished: true, playCount: 1, lastPlayedAt: now)
            ),
            makeEntry(id(7), addedAt: now.addingTimeInterval(-days(1)), collectionID: collectionA),
            makeEntry(id(8), addedAt: now.addingTimeInterval(-days(1)), collectionID: collectionB),
            makeEntry(id(9), addedAt: now.addingTimeInterval(-days(1)), collectionID: nil)
        ]

        for kind in SmartPlaylistKind.allCases {
            let filtered = SmartPlaylistEngine.entries(
                entries,
                kind: kind,
                collectionID: collectionA,
                now: now
            )
            XCTAssertTrue(
                filtered.allSatisfy { $0.collectionID == collectionA && !$0.isMissing },
                "\(kind) leaked an entry from another collection or a missing entry"
            )
        }

        XCTAssertEqual(
            SmartPlaylistEngine.entries(
                entries, kind: .continueListening, collectionID: collectionA, now: now
            ).map(\.id),
            [id(1)]
        )
        XCTAssertEqual(
            SmartPlaylistEngine.entries(
                entries, kind: .unfinished, collectionID: collectionA, now: now
            ).map(\.id),
            [id(1)]
        )
        XCTAssertEqual(
            Set(SmartPlaylistEngine.entries(
                entries, kind: .recentlyAdded, collectionID: collectionA, now: now
            ).map(\.id)),
            Set([id(1), id(5), id(7)])
        )
        XCTAssertEqual(
            SmartPlaylistEngine.entries(
                entries, kind: .finished, collectionID: collectionA, now: now
            ).map(\.id),
            [id(5)]
        )

        // A nil collection ID means "all collections", including items with no
        // collection.
        XCTAssertEqual(
            Set(SmartPlaylistEngine.entries(
                entries, kind: .continueListening, collectionID: nil, now: now
            ).map(\.id)),
            Set([id(1), id(2), id(3)])
        )
        XCTAssertEqual(
            Set(SmartPlaylistEngine.entries(
                entries, kind: .finished, collectionID: nil, now: now
            ).map(\.id)),
            Set([id(5), id(6)])
        )

        assertCountsMatchEntries(entries, collectionID: nil)
        assertCountsMatchEntries(entries, collectionID: collectionA)
        assertCountsMatchEntries(entries, collectionID: collectionB)
    }

    // MARK: - Continue listening and unfinished

    func testContinueAndUnfinishedSharePredicateAndExcludeFinished() {
        let valid = makeEntry(
            id(1),
            playback: makePlayback(
                position: 100,
                playCount: 1,
                lastPlayedAt: now.addingTimeInterval(-10)
            )
        )
        let zeroPosition = makeEntry(id(2), playback: makePlayback(position: 0, playCount: 1))
        let negativePosition = makeEntry(id(3), playback: makePlayback(position: -5, playCount: 1))
        let zeroPlayCount = makeEntry(id(4), playback: makePlayback(position: 100, playCount: 0))
        let negativePlayCount = makeEntry(id(5), playback: makePlayback(position: 100, playCount: -2))
        let finished = makeEntry(
            id(6),
            playback: makePlayback(
                position: 100,
                isFinished: true,
                playCount: 1,
                lastPlayedAt: now
            )
        )
        let noPlayback = makeEntry(id(7))
        let nanPosition = makeEntry(id(8), playback: makePlayback(position: .nan, playCount: 1))
        let infinitePosition = makeEntry(id(9), playback: makePlayback(position: .infinity, playCount: 1))
        let entries = [
            valid,
            zeroPosition,
            negativePosition,
            zeroPlayCount,
            negativePlayCount,
            finished,
            noPlayback,
            nanPosition,
            infinitePosition
        ]

        let continueIDs = SmartPlaylistEngine.entries(
            entries, kind: .continueListening, now: now
        ).map(\.id)
        let unfinishedIDs = SmartPlaylistEngine.entries(
            entries, kind: .unfinished, now: now
        ).map(\.id)

        XCTAssertEqual(continueIDs, [valid.id])
        XCTAssertEqual(unfinishedIDs, [valid.id])
        XCTAssertEqual(continueIDs, unfinishedIDs)
        XCTAssertFalse(continueIDs.contains(finished.id))

        assertCountsMatchEntries(entries)
    }

    func testContinueAndUnfinishedOrderingWithNilLastPlayedAndDeterministicTies() {
        let newest = makeEntry(
            id(2),
            addedAt: now.addingTimeInterval(-10),
            playback: makePlayback(lastPlayedAt: now.addingTimeInterval(-10))
        )
        let sameLastPlayedNewerAdded = makeEntry(
            id(4),
            addedAt: now.addingTimeInterval(-5),
            playback: makePlayback(lastPlayedAt: now.addingTimeInterval(-60))
        )
        let sameLastPlayedOlderAdded = makeEntry(
            id(3),
            addedAt: now.addingTimeInterval(-20),
            playback: makePlayback(lastPlayedAt: now.addingTimeInterval(-60))
        )
        let tieIDHigh = makeEntry(
            id(12),
            addedAt: now.addingTimeInterval(-4),
            playback: makePlayback(lastPlayedAt: now.addingTimeInterval(-30))
        )
        let tieIDLow = makeEntry(
            id(11),
            addedAt: now.addingTimeInterval(-4),
            playback: makePlayback(lastPlayedAt: now.addingTimeInterval(-30))
        )
        let nilLastNewerAdded = makeEntry(
            id(5),
            addedAt: now.addingTimeInterval(-2),
            playback: makePlayback(lastPlayedAt: nil)
        )
        let nilLastOlderAdded = makeEntry(
            id(6),
            addedAt: now.addingTimeInterval(-3),
            playback: makePlayback(lastPlayedAt: nil)
        )
        let entries = [
            sameLastPlayedOlderAdded,
            nilLastOlderAdded,
            tieIDHigh,
            sameLastPlayedNewerAdded,
            newest,
            nilLastNewerAdded,
            tieIDLow
        ]
        let expected = [
            newest.id,
            tieIDLow.id,
            tieIDHigh.id,
            sameLastPlayedNewerAdded.id,
            sameLastPlayedOlderAdded.id,
            nilLastNewerAdded.id,
            nilLastOlderAdded.id
        ]

        let continueResult = SmartPlaylistEngine.entries(
            entries, kind: .continueListening, now: now
        )
        let unfinishedResult = SmartPlaylistEngine.entries(
            entries, kind: .unfinished, now: now
        )

        XCTAssertEqual(continueResult.map(\.id), expected)
        XCTAssertEqual(unfinishedResult.map(\.id), expected)
        XCTAssertEqual(continueResult.count, entries.count, "the engine must not impose a default UI limit")
    }

    // MARK: - Recently added

    func testRecentlyAddedWindowBoundaryFutureAndOldDates() {
        let window = SmartPlaylistEngine.defaultRecentWindow
        let exactlyBoundary = makeEntry(
            id(1),
            addedAt: now.addingTimeInterval(-window)
        )
        let justInside = makeEntry(
            id(2),
            addedAt: now.addingTimeInterval(-window + 1)
        )
        let justOutside = makeEntry(
            id(3),
            addedAt: now.addingTimeInterval(-window - 1)
        )
        let future = makeEntry(
            id(4),
            addedAt: now.addingTimeInterval(days(100))
        )
        let current = makeEntry(id(5), addedAt: now)
        let old = makeEntry(
            id(6),
            addedAt: now.addingTimeInterval(-days(365))
        )
        let missingInsideWindow = makeEntry(id(7), addedAt: now, isMissing: true)
        let entries = [
            old,
            justOutside,
            exactlyBoundary,
            current,
            justInside,
            future,
            missingInsideWindow
        ]

        let result = SmartPlaylistEngine.entries(entries, kind: .recentlyAdded, now: now)
        XCTAssertEqual(
            result.map(\.id),
            [future.id, current.id, justInside.id, exactlyBoundary.id]
        )
        XCTAssertFalse(result.contains { $0.id == justOutside.id })
        XCTAssertFalse(result.contains { $0.id == old.id })
        XCTAssertFalse(result.contains { $0.id == missingInsideWindow.id })
        XCTAssertTrue(
            result.contains { $0.id == exactlyBoundary.id },
            "an item exactly on the window boundary must be included"
        )
        XCTAssertTrue(result.contains { $0.id == future.id }, "future dates must be included")
    }

    func testRecentlyAddedWindowClampsNegativeValuesToZero() {
        let past = makeEntry(id(1), addedAt: now.addingTimeInterval(-1))
        let exactNow = makeEntry(id(2), addedAt: now)
        let future = makeEntry(id(3), addedAt: now.addingTimeInterval(1))
        let entries = [past, exactNow, future]

        let zeroWindow = SmartPlaylistEngine.entries(
            entries, kind: .recentlyAdded, now: now, recentWindow: 0
        )
        XCTAssertEqual(zeroWindow.map(\.id), [future.id, exactNow.id])

        let negativeWindow = SmartPlaylistEngine.entries(
            entries, kind: .recentlyAdded, now: now, recentWindow: -1_000
        )
        XCTAssertEqual(negativeWindow.map(\.id), [future.id, exactNow.id])

        let oneSecondWindow = SmartPlaylistEngine.entries(
            entries, kind: .recentlyAdded, now: now, recentWindow: 1
        )
        XCTAssertEqual(oneSecondWindow.map(\.id), [future.id, exactNow.id, past.id])

        let customWindow = SmartPlaylistEngine.entries(
            [
                makeEntry(id(4), addedAt: now.addingTimeInterval(-days(2))),
                makeEntry(id(5), addedAt: now.addingTimeInterval(-days(4)))
            ],
            kind: .recentlyAdded,
            now: now,
            recentWindow: days(3)
        )
        XCTAssertEqual(customWindow.map(\.id), [id(4)])
    }

    func testRecentlyAddedOrderingAndDeterministicTies() {
        let sharedDate = now.addingTimeInterval(-days(2))
        let idHigh = makeEntry(id(30), addedAt: sharedDate)
        let idLow = makeEntry(id(20), addedAt: sharedDate)
        let newest = makeEntry(id(40), addedAt: now.addingTimeInterval(-days(1)))
        let oldest = makeEntry(id(10), addedAt: now.addingTimeInterval(-days(3)))

        let result = SmartPlaylistEngine.entries(
            [idHigh, oldest, idLow, newest],
            kind: .recentlyAdded,
            now: now
        )

        XCTAssertEqual(result.map(\.id), [newest.id, idLow.id, idHigh.id, oldest.id])
    }

    // MARK: - Finished

    func testFinishedIgnoresPositionAndOrdersByLastPlayedThenAddedAtThenID() {
        let recentlyPlayed = makeEntry(
            id(1),
            addedAt: now.addingTimeInterval(-100),
            playback: makePlayback(
                position: 0,
                isFinished: true,
                playCount: 0,
                lastPlayedAt: now.addingTimeInterval(-10)
            )
        )
        let nanPosition = makeEntry(
            id(2),
            addedAt: now.addingTimeInterval(-100),
            playback: makePlayback(
                position: .nan,
                isFinished: true,
                playCount: -4,
                lastPlayedAt: now.addingTimeInterval(-20)
            )
        )
        let nilLastNewerAdded = makeEntry(
            id(3),
            addedAt: now.addingTimeInterval(-1),
            playback: makePlayback(
                position: -50,
                isFinished: true,
                playCount: 0,
                lastPlayedAt: nil
            )
        )
        let nilLastOlderAdded = makeEntry(
            id(4),
            addedAt: now.addingTimeInterval(-2),
            playback: makePlayback(
                position: 100,
                isFinished: true,
                playCount: 9,
                lastPlayedAt: nil
            )
        )
        let tieIDHigh = makeEntry(
            id(12),
            addedAt: now.addingTimeInterval(-5),
            playback: makePlayback(
                position: 1,
                isFinished: true,
                lastPlayedAt: now.addingTimeInterval(-30)
            )
        )
        let tieIDLow = makeEntry(
            id(11),
            addedAt: now.addingTimeInterval(-5),
            playback: makePlayback(
                position: 1,
                isFinished: true,
                lastPlayedAt: now.addingTimeInterval(-30)
            )
        )
        let notFinished = makeEntry(
            id(5),
            playback: makePlayback(
                position: 999,
                isFinished: false,
                playCount: 3,
                lastPlayedAt: now
            )
        )
        let noPlayback = makeEntry(id(6))

        let result = SmartPlaylistEngine.entries(
            [
                nilLastOlderAdded,
                notFinished,
                tieIDHigh,
                recentlyPlayed,
                nilLastNewerAdded,
                noPlayback,
                nanPosition,
                tieIDLow
            ],
            kind: .finished,
            now: now
        )

        XCTAssertEqual(
            result.map(\.id),
            [
                recentlyPlayed.id,
                nanPosition.id,
                tieIDLow.id,
                tieIDHigh.id,
                nilLastNewerAdded.id,
                nilLastOlderAdded.id
            ]
        )
        XCTAssertFalse(result.contains { $0.id == notFinished.id })
        XCTAssertFalse(result.contains { $0.id == noPlayback.id })
    }

    // MARK: - Limit

    func testLimitIsAppliedAfterFilteringAndSorting() {
        let playbacks = (1...5).map { index in
            makeEntry(
                id(index),
                collectionID: collectionA,
                playback: makePlayback(
                    position: 10,
                    playCount: 1,
                    lastPlayedAt: now.addingTimeInterval(Double(-index))
                )
            )
        }
        let missingFirst = makeEntry(
            id(99),
            collectionID: collectionA,
            isMissing: true,
            playback: makePlayback(position: 10, playCount: 1, lastPlayedAt: now.addingTimeInterval(100))
        )
        let otherCollectionFirst = makeEntry(
            id(98),
            collectionID: collectionB,
            playback: makePlayback(position: 10, playCount: 1, lastPlayedAt: now.addingTimeInterval(100))
        )
        let entries = [missingFirst, otherCollectionFirst] + playbacks
        let expectedOrder = playbacks.map(\.id)

        let unlimited = SmartPlaylistEngine.entries(
            entries,
            kind: .continueListening,
            collectionID: collectionA,
            now: now
        )
        XCTAssertEqual(unlimited.map(\.id), expectedOrder)

        let explicitNil = SmartPlaylistEngine.entries(
            entries,
            kind: .continueListening,
            collectionID: collectionA,
            now: now,
            limit: nil
        )
        XCTAssertEqual(explicitNil.map(\.id), expectedOrder)

        XCTAssertTrue(
            SmartPlaylistEngine.entries(
                entries,
                kind: .continueListening,
                collectionID: collectionA,
                now: now,
                limit: 0
            ).isEmpty
        )
        XCTAssertTrue(
            SmartPlaylistEngine.entries(
                entries,
                kind: .continueListening,
                collectionID: collectionA,
                now: now,
                limit: -2
            ).isEmpty
        )

        let limited = SmartPlaylistEngine.entries(
            entries,
            kind: .continueListening,
            collectionID: collectionA,
            now: now,
            limit: 2
        )
        XCTAssertEqual(limited.map(\.id), Array(expectedOrder.prefix(2)))

        XCTAssertEqual(
            SmartPlaylistEngine.entries(
                entries,
                kind: .continueListening,
                collectionID: collectionA,
                now: now,
                limit: 10
            ).map(\.id),
            expectedOrder
        )
    }

    func testLimitAlsoAppliesToRecentlyAddedAndFinished() {
        let recent = [
            makeEntry(id(1), addedAt: now),
            makeEntry(id(2), addedAt: now.addingTimeInterval(-1)),
            makeEntry(id(3), addedAt: now.addingTimeInterval(-2))
        ]
        XCTAssertEqual(
            SmartPlaylistEngine.entries(recent, kind: .recentlyAdded, now: now, limit: 2).map(\.id),
            [id(1), id(2)]
        )
        XCTAssertTrue(
            SmartPlaylistEngine.entries(recent, kind: .recentlyAdded, now: now, limit: 0).isEmpty
        )

        let finished = [
            makeEntry(
                id(4),
                playback: makePlayback(
                    position: 100,
                    isFinished: true,
                    lastPlayedAt: now.addingTimeInterval(-1)
                )
            ),
            makeEntry(
                id(5),
                playback: makePlayback(
                    position: 100,
                    isFinished: true,
                    lastPlayedAt: now
                )
            ),
            makeEntry(
                id(6),
                playback: makePlayback(
                    position: 100,
                    isFinished: true,
                    lastPlayedAt: nil
                )
            )
        ]
        XCTAssertEqual(
            SmartPlaylistEngine.entries(finished, kind: .finished, now: now, limit: 1).map(\.id),
            [id(5)]
        )
        XCTAssertEqual(
            SmartPlaylistEngine.entries(finished, kind: .finished, now: now, limit: -1),
            []
        )
    }

    // MARK: - Counts

    func testCountsMatchEntriesForAllKindsAndFilters() {
        let entries = [
            makeEntry(
                id(1),
                addedAt: now,
                collectionID: collectionA,
                playback: makePlayback(
                    position: 30,
                    playCount: 2,
                    lastPlayedAt: now.addingTimeInterval(-10)
                )
            ),
            makeEntry(
                id(2),
                addedAt: now.addingTimeInterval(-days(2)),
                collectionID: collectionA,
                playback: makePlayback(
                    position: 30,
                    isFinished: true,
                    playCount: 2,
                    lastPlayedAt: now.addingTimeInterval(-20)
                )
            ),
            makeEntry(
                id(3),
                addedAt: now.addingTimeInterval(-days(40)),
                collectionID: collectionB,
                playback: makePlayback(position: 0, playCount: 0)
            ),
            makeEntry(id(4), addedAt: now.addingTimeInterval(-days(1)), collectionID: nil),
            makeEntry(
                id(5),
                addedAt: now,
                collectionID: collectionA,
                isMissing: true,
                playback: makePlayback(position: 30, playCount: 1)
            ),
            makeEntry(
                id(6),
                addedAt: now.addingTimeInterval(-days(10)),
                collectionID: collectionA,
                playback: makePlayback(
                    position: 5,
                    playCount: 1,
                    lastPlayedAt: nil
                )
            )
        ]

        assertCountsMatchEntries(entries, collectionID: nil)
        assertCountsMatchEntries(entries, collectionID: collectionA)
        assertCountsMatchEntries(entries, collectionID: collectionB)

        let counts = SmartPlaylistEngine.counts(entries, now: now)
        XCTAssertEqual(Set(counts.keys), Set(SmartPlaylistKind.allCases))
        XCTAssertEqual(counts[.continueListening], 2)
        XCTAssertEqual(counts[.unfinished], 2)
        XCTAssertEqual(counts[.recentlyAdded], 4)
        XCTAssertEqual(counts[.finished], 1)

        let countsA = SmartPlaylistEngine.counts(entries, collectionID: collectionA, now: now)
        XCTAssertEqual(countsA[.continueListening], 2)
        XCTAssertEqual(countsA[.unfinished], 2)
        XCTAssertEqual(countsA[.recentlyAdded], 3)
        XCTAssertEqual(countsA[.finished], 1)

        let countsB = SmartPlaylistEngine.counts(entries, collectionID: collectionB, now: now)
        XCTAssertEqual(countsB[.continueListening], 0)
        XCTAssertEqual(countsB[.unfinished], 0)
        XCTAssertEqual(countsB[.recentlyAdded], 0)
        XCTAssertEqual(countsB[.finished], 0)
    }

    func testEmptyLibraryCountsAreZeroForEveryKind() {
        let counts = SmartPlaylistEngine.counts([], now: now)
        XCTAssertEqual(
            counts,
            [
                .continueListening: 0,
                .unfinished: 0,
                .recentlyAdded: 0,
                .finished: 0
            ]
        )
    }

    // MARK: - Invalid values

    func testInvalidDatesAndNonFiniteValuesAreHandledDefensively() {
        let invalidDate = Date(timeIntervalSinceReferenceDate: .nan)
        let infiniteDate = Date(timeIntervalSinceReferenceDate: .infinity)

        let nanPosition = makeEntry(
            id(1),
            playback: makePlayback(position: .nan, playCount: 1)
        )
        let infinitePosition = makeEntry(
            id(2),
            playback: makePlayback(position: .infinity, playCount: 1)
        )
        let negativeInfinitePosition = makeEntry(
            id(3),
            playback: makePlayback(position: -.infinity, playCount: 1)
        )
        let valid = makeEntry(
            id(4),
            playback: makePlayback(position: 1, playCount: 1, lastPlayedAt: now)
        )

        let inProgress = SmartPlaylistEngine.entries(
            [nanPosition, infinitePosition, negativeInfinitePosition, valid],
            kind: .continueListening,
            now: now
        )
        XCTAssertEqual(inProgress.map(\.id), [valid.id])

        let invalidLastPlayed = makeEntry(
            id(5),
            addedAt: now.addingTimeInterval(-1),
            playback: makePlayback(lastPlayedAt: invalidDate)
        )
        let infiniteLastPlayed = makeEntry(
            id(6),
            addedAt: now.addingTimeInterval(-2),
            playback: makePlayback(lastPlayedAt: infiniteDate)
        )
        let validLastPlayed = makeEntry(
            id(7),
            addedAt: now.addingTimeInterval(-100),
            playback: makePlayback(lastPlayedAt: now.addingTimeInterval(-1_000))
        )
        let ordered = SmartPlaylistEngine.entries(
            [invalidLastPlayed, infiniteLastPlayed, validLastPlayed],
            kind: .unfinished,
            now: now
        )
        XCTAssertEqual(
            ordered.map(\.id),
            [validLastPlayed.id, invalidLastPlayed.id, infiniteLastPlayed.id]
        )

        let invalidAddedAt = makeEntry(id(8), addedAt: invalidDate)
        let validAddedAt = makeEntry(id(9), addedAt: now)
        let recent = SmartPlaylistEngine.entries(
            [invalidAddedAt, validAddedAt],
            kind: .recentlyAdded,
            now: now
        )
        XCTAssertEqual(recent.map(\.id), [validAddedAt.id])

        let counts = SmartPlaylistEngine.counts(
            [nanPosition, infinitePosition, negativeInfinitePosition, valid, invalidAddedAt],
            now: now
        )
        XCTAssertEqual(counts[.continueListening], 1)
        XCTAssertEqual(counts[.unfinished], 1)
        // The four entries with a valid addedAt are recent; the NaN date is not.
        XCTAssertEqual(counts[.recentlyAdded], 4)
        XCTAssertEqual(counts[.finished], 0)
    }
}
