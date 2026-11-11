import XCTest

@MainActor
final class P1SmartPlaylistUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeApp(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchPinned()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func tapTab(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing tab \(label)")
        button.tap()
    }

    private func openPlaylists(in app: XCUIApplication) {
        tapTab("资料库", in: app)
        let link = element(app, "libraryPlaylistsLink")
        XCTAssertTrue(link.waitForExistence(timeout: 20))
        link.tap()
        XCTAssertTrue(
            element(app, "smartPlaylistRow-continueListening").waitForExistence(timeout: 10),
            "Smart playlist section did not appear"
        )
    }

    private func goBack(in app: XCUIApplication) {
        let back = app.buttons["BackButton"].firstMatch
        if back.waitForExistence(timeout: 5) {
            back.tap()
            return
        }
        let navBack = app.navigationBars.firstMatch.buttons.firstMatch
        if navBack.waitForExistence(timeout: 2) {
            navBack.tap()
            return
        }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func smartCount(
        _ kind: String,
        in app: XCUIApplication
    ) -> String {
        let count = element(app, "smartPlaylistCount-\(kind)")
        if count.exists, !count.label.isEmpty {
            return count.label
        }
        let row = element(app, "smartPlaylistRow-\(kind)")
        return (row.value as? String) ?? "?"
    }

    func testSmartPlaylistCountsAndContinueListening() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m3-seed-playable-library",
            "--p1-seed-smart-playlists"
        ])
        openPlaylists(in: app)

        XCTAssertEqual(smartCount("continueListening", in: app), "1")
        XCTAssertEqual(smartCount("unfinished", in: app), "1")
        XCTAssertEqual(smartCount("finished", in: app), "1")
        XCTAssertEqual(smartCount("recentlyAdded", in: app), "3")

        element(app, "smartPlaylistRow-continueListening").tap()
        XCTAssertTrue(
            element(app, "smartPlaylistItem-队列测试 C").waitForExistence(timeout: 10)
        )
        XCTAssertFalse(
            element(app, "smartPlaylistItem-队列测试 B").exists,
            "Finished item must not appear under Continue Listening"
        )
        XCTAssertFalse(
            element(app, "smartPlaylistItem-队列测试 A").exists,
            "Unplayed item must not appear under Continue Listening"
        )
        attachScreenshot(app, name: "P1-smart-continue")
    }

    func testFinishedListAndCollectionFilter() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m3-seed-playable-library",
            "--p1-seed-smart-playlists"
        ])
        openPlaylists(in: app)

        element(app, "smartPlaylistRow-finished").tap()
        XCTAssertTrue(
            element(app, "smartPlaylistItem-队列测试 B").waitForExistence(timeout: 10)
        )
        XCTAssertFalse(element(app, "smartPlaylistItem-队列测试 C").exists)
        attachScreenshot(app, name: "P1-smart-finished")
        goBack(in: app)

        let byCollection = element(app, "smartPlaylistRow-byCollection")
        XCTAssertTrue(byCollection.waitForExistence(timeout: 10))
        byCollection.tap()
        let collectionA = element(app, "smartCollectionRow-智能合集 A")
        XCTAssertTrue(collectionA.waitForExistence(timeout: 10))
        collectionA.tap()

        XCTAssertTrue(
            element(app, "smartCollectionItem-队列测试 A").waitForExistence(timeout: 10)
        )
        XCTAssertTrue(element(app, "smartCollectionItem-队列测试 C").exists)
        XCTAssertFalse(
            element(app, "smartCollectionItem-队列测试 B").exists,
            "Collection A must not include collection B's item"
        )
        attachScreenshot(app, name: "P1-smart-collection")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
