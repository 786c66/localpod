import XCTest

/// Shortcuts/Siri launch-request coverage. The app side has no App Intents UI
/// tests (Siri cannot be scripted reliably); the `--p2-app-intent=` launch seam
/// stages the same UserDefaults request the intents persist, so these tests
/// exercise the real cold-launch consumption path.
@MainActor
final class P2ShortcutUITests: XCTestCase {
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

    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 6
    ) {
        var resets = 0
        while !(element.exists && element.isHittable), resets < 4 {
            app.swipeDown()
            resets += 1
        }
        var attempts = 0
        while !(element.exists && element.isHittable), attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
        }
    }

    private func waitForLabel(
        _ element: XCUIElement,
        equals expected: String,
        timeout: TimeInterval
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expected),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "expected label \(expected), got \(element.label)"
        )
    }

    private func seconds(from label: String) -> Int {
        let parts = label.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return 0 }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        return parts[0]
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// "继续播放" (continue-playback) must autoplay the restored queue's current
    /// item (fixture A) and the playhead must advance.
    func testContinuePlaybackLaunchRequestStartsQueue() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m3-seed-playable-library",
            "--m3-seed-queue",
            "--p2-app-intent=continue-playback"
        ])

        // The intent switches to the player tab itself. Do NOT tap the tab
        // button here: tapping an already-selected tab pops the tab's
        // navigation stack to its root, which would hide the pushed detail.
        let title = element(app, "currentPlaybackTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertEqual(title.label, "队列测试 A")

        let playPause = element(app, "playPauseButton")
        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        reveal(playPause, in: app)

        // The phase sticker is gone from the playback screen; advancing time
        // is the observable proof that the intent actually started playback.
        let time = element(app, "currentTimeText")
        XCTAssertTrue(time.waitForExistence(timeout: 10))
        let before = seconds(from: time.label)
        sleep(2)
        let after = seconds(from: time.label)
        XCTAssertGreaterThan(
            after,
            before,
            "playback time did not advance (\(before)s -> \(after)s)"
        )
        attachScreenshot(app, name: "P2-shortcut-continue-playback")
    }

    /// "打开合集" (open-collection) must push the matching collection detail.
    /// Fallback: if the detail cannot be pushed, the library must at least be
    /// on the collections scope with the requested name in search.
    func testOpenCollectionLaunchRequestOpensDetail() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m3-seed-playable-library",
            "--p1-seed-smart-playlists",
            "--p2-app-intent=open-collection:智能合集 B"
        ])

        // The intent selects the library tab and pushes the detail itself.
        // Do NOT tap the already-selected 资料库 tab: that pops the pushed
        // detail back to the library root.
        let playAll = element(app, "collectionPlayAllButton")
        if playAll.waitForExistence(timeout: 20) {
            reveal(playAll, in: app)
            let navigationTitle = app.navigationBars["智能合集 B"]
            let staticTitle = app.staticTexts["智能合集 B"].firstMatch
            XCTAssertTrue(
                navigationTitle.waitForExistence(timeout: 10) || staticTitle.exists,
                "collection name is not visible in the detail"
            )
        } else {
            // Fallback: the library must switch to the collections scope and
            // show the requested name as an active filter. There is no search
            // UI any more, so assert the filtered result + the removable
            // filter chip instead of a search field.
            // Do not assert the segmented control's `isSelected`: SwiftUI does
            // not reliably expose selection on segmented-picker segments.
            let collectionRow = element(app, "collectionRow-智能合集 B")
            XCTAssertTrue(
                collectionRow.waitForExistence(timeout: 5),
                "fallback did not switch the library to the collections scope"
            )
            let filterChip = element(app, "librarySearchFilterChip")
            XCTAssertTrue(
                filterChip.waitForExistence(timeout: 5),
                "fallback did not surface the requested name as a filter"
            )
            XCTAssertTrue(
                filterChip.label.contains("智能合集 B"),
                "filter chip does not name the requested collection: \(filterChip.label)"
            )
            XCTAssertTrue(
                element(app, "librarySearchFilterClearButton").exists,
                "active filter is not removable"
            )
        }
        XCTAssertEqual(
            app.searchFields.count,
            0,
            "the library must not expose any search field"
        )
        attachScreenshot(app, name: "P2-shortcut-open-collection")
    }

    /// The search UI is gone, so a name that matches no collection must land
    /// as a removable filter chip on the collections scope: the filtered
    /// result is visible (no-match empty state), nothing crashes, and
    /// clearing the chip restores the full grid.
    func testOpenCollectionPrefillShowsRemovableFilter() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m3-seed-playable-library",
            "--p1-seed-smart-playlists",
            "--p2-app-intent=open-collection:不存在的合集"
        ])

        let filterChip = element(app, "librarySearchFilterChip")
        XCTAssertTrue(
            filterChip.waitForExistence(timeout: 20),
            "prefill did not surface as a filter chip"
        )
        XCTAssertTrue(
            filterChip.label.contains("不存在的合集"),
            "filter chip does not name the requested collection: \(filterChip.label)"
        )
        XCTAssertEqual(
            app.searchFields.count,
            0,
            "the library must not expose any search field"
        )

        // The filter actually applies: no seeded collection matches.
        XCTAssertTrue(
            element(app, "collectionEmptyState").waitForExistence(timeout: 5),
            "filtered collections grid did not show the no-match state"
        )

        // Clearing the chip restores the unfiltered library.
        let clear = element(app, "librarySearchFilterClearButton")
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "filter is not removable")
        clear.tap()
        XCTAssertFalse(
            filterChip.waitForExistence(timeout: 3),
            "filter chip did not disappear after clearing"
        )
        XCTAssertTrue(
            element(app, "collectionRow-智能合集 A").waitForExistence(timeout: 5),
            "clearing the filter did not restore the collections grid"
        )
        attachScreenshot(app, name: "P2-shortcut-filter-cleared")
    }
}
