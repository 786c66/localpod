import Foundation
import XCTest
@testable import LocalPodKit

final class CollectionOrderingTests: XCTestCase {
    private func item(
        _ title: String,
        path: String = "",
        name: String? = nil,
        addedAt: Date = Date(timeIntervalSince1970: 0),
        position: Int = 0
    ) -> MediaItem {
        MediaItem(
            title: title,
            originalFileName: name ?? "\(title).m4a",
            relativePath: "Media/\(title).m4a",
            relativeFolderPath: path,
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 1,
            addedAt: addedAt,
            collectionPosition: position
        )
    }

    func testNaturalSortIsNumericAware() {
        let items = [
            item("Episode 10"),
            item("Episode 2"),
            item("Episode 1")
        ]
        XCTAssertEqual(
            CollectionOrdering.sorted(items, by: .natural).map(\.title),
            ["Episode 1", "Episode 2", "Episode 10"]
        )
    }

    func testNaturalSortUsesSourcePathBeforeTitle() {
        let items = [
            item("Alpha", path: "Season 2"),
            item("Zulu", path: "Season 1")
        ]
        XCTAssertEqual(
            CollectionOrdering.sorted(items, by: .natural).map(\.title),
            ["Zulu", "Alpha"]
        )
    }

    func testNaturalDescendingIsExactReverse() {
        let items = [
            item("Episode 1"),
            item("Episode 2"),
            item("Episode 10")
        ]
        XCTAssertEqual(
            CollectionOrdering.sorted(items, by: .naturalDescending).map(\.title),
            ["Episode 10", "Episode 2", "Episode 1"]
        )
    }

    func testNameSortUsesTitle() {
        let items = [
            item("beta", path: "a"),
            item("Alpha", path: "z"),
            item("Gamma", path: "m")
        ]
        XCTAssertEqual(
            CollectionOrdering.sorted(items, by: .name).map(\.title),
            ["Alpha", "beta", "Gamma"]
        )
    }

    func testImportedAtSortUsesAddedDate() {
        let items = [
            item("Second", addedAt: Date(timeIntervalSince1970: 2_000)),
            item("First", addedAt: Date(timeIntervalSince1970: 1_000)),
            item("Third", addedAt: Date(timeIntervalSince1970: 3_000))
        ]
        XCTAssertEqual(
            CollectionOrdering.sorted(items, by: .importedAt).map(\.title),
            ["First", "Second", "Third"]
        )
    }

    func testManualSortUsesAssignedPositionsAndBreaksTiesByTitle() {
        let items = [
            item("B", position: 1),
            item("A", position: 1),
            item("C", position: 0)
        ]
        XCTAssertEqual(
            CollectionOrdering.sorted(items, by: .manual).map(\.title),
            ["C", "A", "B"]
        )
    }

    func testAssignManualPositionsRewritesFromVisibleOrder() {
        let first = item("A")
        let second = item("B")
        let third = item("C")
        CollectionOrdering.assignManualPositions([third, first, second])

        XCTAssertEqual(third.collectionPosition, 0)
        XCTAssertEqual(first.collectionPosition, 1)
        XCTAssertEqual(second.collectionPosition, 2)
        XCTAssertEqual(
            CollectionOrdering.sorted([first, second, third], by: .manual).map(\.title),
            ["C", "A", "B"]
        )
    }

    func testMovingAppliesListSemantics() {
        let items = [item("A"), item("B"), item("C")]

        let movedDown = CollectionOrdering.moving(
            items,
            fromOffsets: IndexSet(integer: 0),
            toOffset: 3
        )
        XCTAssertEqual(movedDown.map(\.title), ["B", "C", "A"])

        let movedUp = CollectionOrdering.moving(
            items,
            fromOffsets: IndexSet(integer: 2),
            toOffset: 0
        )
        XCTAssertEqual(movedUp.map(\.title), ["C", "A", "B"])
    }

    func testSourceKeyUsesFolderPathAndFileName() {
        XCTAssertEqual(CollectionOrdering.sourceKey(for: item("X")), "X.m4a")
        XCTAssertEqual(
            CollectionOrdering.sourceKey(for: item("X", path: "Season 1")),
            "Season 1/X.m4a"
        )
    }

    func testCollectionSortModeRoundTripsRawValue() {
        for mode in CollectionSortMode.allCases {
            XCTAssertEqual(CollectionSortMode(rawValue: mode.rawValue), mode)
        }
    }

    func testSortModeDisplayNamesAreLocalized() {
        for mode in CollectionSortMode.allCases {
            let zh = mode.displayName(locale: Locale(identifier: "zh-Hans"))
            let en = mode.displayName(locale: Locale(identifier: "en"))
            XCTAssertFalse(zh.contains("collection.sort"), "\(mode) zh")
            XCTAssertFalse(en.contains("collection.sort"), "\(mode) en")
            XCTAssertNotEqual(zh, en, "\(mode) should differ between zh and en")
        }
    }
}
