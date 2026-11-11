import XCTest

/// P2 trash (回收站) UI tests. Seams:
/// - `--m3-seed-playable-library` puts three items (队列测试 A/B/C) in the
///   library with real demo-audio files, the most battle-tested seeding path;
/// - `--p2-seed-expired-trash` seeds one already-expired trash row whose
///   purge runs during launch bootstrap (reconcile → purgeExpired).
@MainActor
final class P2TrashUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 12
    ) {
        // Swipe one at a time with a hittability check, reversing direction
        // after the first pass (same helper as P1/P2 suites).
        var attempts = 0
        while !(element.exists && element.isHittable), attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
        }
        var back = 0
        while !(element.exists && element.isHittable), back < maxSwipes {
            app.swipeDown()
            back += 1
        }
        XCTAssertTrue(
            element.exists && element.isHittable,
            "Element \(element) did not become hittable after scrolling"
        )
    }

    private func tapLibraryTab(_ app: XCUIApplication) {
        let button = app.buttons["资料库"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Missing 资料库 tab")
        button.tap()
    }

    /// Waits for the library's stats row, the first content the Library tab
    /// renders, so later queries never race the first frame.
    private func waitForLibrary(_ app: XCUIApplication) {
        tapLibraryTab(app)
        let stats = element(app, "libraryStatsText")
        reveal(stats, in: app)
        XCTAssertTrue(stats.waitForExistence(timeout: 20))
    }

    /// Mirrors M3's goBack: iOS 27 exposes the floating back control as a
    /// standalone "BackButton" outside the NavigationBar element; older
    /// versions put it in the bar; the edge swipe is the last resort.
    private func goBack(in app: XCUIApplication) {
        let backButton = app.buttons["BackButton"].firstMatch
        if backButton.waitForExistence(timeout: 5) {
            backButton.tap()
            return
        }
        let button = app.navigationBars.firstMatch.buttons.firstMatch
        if button.waitForExistence(timeout: 2) {
            button.tap()
            return
        }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(
            app.navigationBars.firstMatch.waitForExistence(timeout: 5),
            "Could not navigate back"
        )
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDeleteGoesToTrashAndRestore() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--m0-reset-data",
            "--m3-seed-playable-library"
        ]
        app.launchPinned()
        waitForLibrary(app)

        // Three seeded items in the library.
        let rowA = element(app, "libraryItem-队列测试 A")
        reveal(rowA, in: app)
        XCTAssertTrue(rowA.waitForExistence(timeout: 20))

        // Delete item A through the existing detail delete flow.
        rowA.tap()
        let delete = element(app, "detailDeleteButton")
        reveal(delete, in: app)
        delete.tap()
        let confirm = app.alerts.buttons.matching(
            NSPredicate(format: "label == %@", "移到回收站")
        ).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()

        // Back on the library list, item A is gone and the trash section
        // (added at the bottom, after existing content) shows 1 条.
        let stats = element(app, "libraryStatsText")
        reveal(stats, in: app)
        XCTAssertFalse(
            element(app, "libraryItem-队列测试 A").exists,
            "Deleted item must leave the library list"
        )
        let trashCount = element(app, "trashCountText")
        reveal(trashCount, in: app)
        XCTAssertEqual(trashCount.label, "1 条", "Trash section must show 1 item")

        // Open the trash and restore item A.
        let trashLink = element(app, "trashSectionLink")
        reveal(trashLink, in: app)
        trashLink.tap()
        let trashRow = element(app, "trashItem-队列测试 A")
        XCTAssertTrue(
            trashRow.waitForExistence(timeout: 10),
            "Trash list must show the deleted item"
        )

        let restore = element(app, "trashRestore-队列测试 A")
        reveal(restore, in: app)
        restore.tap()

        // Trash empties out after the restore.
        XCTAssertTrue(
            element(app, "trashEmptyState").waitForExistence(timeout: 10),
            "Trash must be empty after restoring the only item"
        )

        // Back to the library: item A is restored (same row identifier).
        goBack(in: app)
        waitForLibrary(app)
        let backRow = element(app, "libraryItem-队列测试 A")
        reveal(backRow, in: app)
        XCTAssertTrue(
            backRow.waitForExistence(timeout: 20),
            "Restored item must reappear in the library"
        )
        attachScreenshot(app, name: "P2-trash-restored")
    }

    func testExpiredTrashPurgesOnLaunch() throws {
        let app = XCUIApplication()
        // The expired row is purged during launch bootstrap (maintenance runs
        // before the first frame), so the trash UI shows the empty state.
        app.launchArguments = [
            "--m0-reset-data",
            "--p2-seed-expired-trash"
        ]
        app.launchPinned()
        waitForLibrary(app)

        let trashCount = element(app, "trashCountText")
        reveal(trashCount, in: app)
        XCTAssertEqual(
            trashCount.label, "0 条",
            "Expired trash row must be purged at launch"
        )

        // Opening the trash shows the empty state, not a crashed/looping list.
        let trashLink = element(app, "trashSectionLink")
        reveal(trashLink, in: app)
        trashLink.tap()
        XCTAssertTrue(
            element(app, "trashEmptyState").waitForExistence(timeout: 10),
            "Purged trash must render the empty state"
        )
        XCTAssertFalse(
            element(app, "trashItem-回收站过期条目").exists,
            "The expired item must be gone"
        )
        attachScreenshot(app, name: "P2-trash-expired-purged")
    }
}
