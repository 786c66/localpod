import XCTest

/// P2 linked-folder UI tests. Both tests rely on the P2 debug seams:
/// `--p2-seed-linked-folder` creates tmp/P2LinkedDemo with one audio file and
/// a LinkedFolder row; `--p2-stale-linked-folder` seeds and then removes the
/// directory so the bookmark cannot resolve.
@MainActor
final class P2LinkedFolderUITests: XCTestCase {
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
        // Mirrors the P1 helper: swipe one at a time with a hittability check,
        // reversing direction after the first pass, because a fixed multi-swipe
        // run can overshoot the lazy row and a downward reset can dismiss the
        // settings sheet.
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

    private func openSettings(in app: XCUIApplication) {
        let settingsButton = element(app, "librarySettingsButton")
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 20))
        settingsButton.tap()
        XCTAssertTrue(
            element(app, "settingsCloseButton").waitForExistence(timeout: 20),
            "Settings sheet did not open"
        )
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStaleLinkedFolderShowsRelink() throws {
        let app = XCUIApplication()
        // --p2-stale-linked-folder seeds the row then removes tmp/P2LinkedDemo;
        // --p2-check-stale-linked-folders makes the settings page re-resolve
        // all bookmarks once on appear so the badge shows without a sync tap.
        app.launchArguments = [
            "--m0-reset-data",
            "--p2-stale-linked-folder",
            "--p2-check-stale-linked-folders"
        ]
        app.launchPinned()

        openSettings(in: app)

        // The stale row lives between the Wi-Fi section and 导入历史.
        let section = element(app, "linkedFoldersSection")
        reveal(section, in: app)
        let badge = element(app, "linkedFolderStaleBadge")
        XCTAssertTrue(
            badge.waitForExistence(timeout: 10),
            "Stale badge must show when the linked folder no longer resolves"
        )
        let relink = element(app, "linkedFolderRelinkButton")
        reveal(relink, in: app)
        XCTAssertTrue(relink.exists, "Stale rows must offer 重新选择文件夹")
        XCTAssertTrue(
            element(app, "linkedFolderSyncSummary-P2LinkedDemo").exists,
            "Never-synced summary should be visible for the stale row"
        )
        attachScreenshot(app, name: "P2-linked-folder-stale")
    }

    func testLinkedFolderSyncsAndImportsNewFile() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--m0-reset-data", "--p2-seed-linked-folder"]
        app.launchPinned()

        openSettings(in: app)

        let section = element(app, "linkedFoldersSection")
        reveal(section, in: app)

        // Single linked folder → the stable sync button id.
        let sync = element(app, "linkedFolderSync")
        XCTAssertTrue(
            sync.waitForExistence(timeout: 10),
            "Seeded linked folder row with 立即同步 button must appear"
        )
        reveal(sync, in: app)
        sync.tap()

        // The sync runs the real import pipeline; the summary refreshes with
        // the new count once it finishes.
        let summary = element(app, "linkedFolderSyncSummary-P2LinkedDemo")
        let predicate = NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@",
            "上次同步", "新增 1"
        )
        let expectation = expectation(
            for: predicate,
            evaluatedWith: summary
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 60),
            .completed,
            "Sync summary never showed 上次同步/新增 1: \(summary.exists ? summary.label : "missing")"
        )

        // The imported item must exist in the library (source: linked folder
        // → collection P2LinkedDemo → item Episode 01).
        let libraryTab = app.buttons["资料库"].firstMatch
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 20))
        libraryTab.tap()
        let row = element(app, "libraryItem-Episode 01")
        XCTAssertTrue(
            row.waitForExistence(timeout: 30),
            "Synced file was not imported into the library"
        )
        attachScreenshot(app, name: "P2-linked-folder-synced")
    }
}
