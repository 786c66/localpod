import XCTest

/// P2 chapters (章节) UI test. Seam: `--p2-chapter-playback` plays the bundled
/// chaptered fixture (180 s, 3 × 60 s chapters) at launch, so no library data
/// is seeded and the player card shows the chapter section directly.
@MainActor
final class P2ChapterUITests: XCTestCase {
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

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Parses "m:ss" (and "h:mm:ss") labels into seconds.
    private func seconds(from label: String) -> Int? {
        let parts = label.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        return parts[0] * 60 + parts[1]
    }

    func testChapterListShowsAndSeeksToChapter() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--m0-reset-data",
            "--p2-chapter-playback"
        ]
        app.launchPinned()

        // Player card is up with the chaptered fixture loaded.
        let title = element(app, "currentPlaybackTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertEqual(title.label, "章节音频测试")

        // Pause first: the time labels refresh every 0.5 s while playing,
        // which churns the layout below them. A paused card keeps the
        // scroll-and-tap sequence deterministic.
        let playPause = element(app, "playPauseButton")
        reveal(playPause, in: app)
        XCTAssertTrue(playPause.waitForExistence(timeout: 5))
        playPause.tap()

        // The chapter section renders three rows after the sleep-timer row.
        let header = element(app, "chapterSectionHeader")
        reveal(header, in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertEqual(header.label, "章节 · 3")
        let row0 = element(app, "chapterRowCurrent")
        reveal(row0, in: app)
        XCTAssertTrue(row0.waitForExistence(timeout: 10))
        XCTAssertEqual(row0.label, "第 1 章：Chapter One，开始于 0:00")
        let row1 = element(app, "chapterRow-1")
        let row2 = element(app, "chapterRow-2")
        XCTAssertTrue(row1.waitForExistence(timeout: 5), "chapter row 1 must exist")
        XCTAssertTrue(row2.waitForExistence(timeout: 5), "chapter row 2 must exist")
        attachScreenshot(app, name: "P2-chapter-list")

        // Tap the third chapter; the seek updates the time label immediately
        // and the current-chapter indicator moves to row 2.
        //
        // History: early runs failed here because the row's Spacer middle is
        // not hit-testable — XCUITest taps the a11y frame's center, which
        // lands in the transparent gap, so the tap fell through to the List
        // row. The view now applies .contentShape(Rectangle()) over the
        // whole row (also a real UX fix: users tap the empty middle too).
        reveal(row2, in: app)
        row2.tap()

        // The current-chapter indicator must now be row 2 (identifier swaps
        // from chapterRow-2 to chapterRowCurrent). Hard assertion: this is
        // the end-to-end verification of tap-to-seek.
        let currentRow = element(app, "chapterRowCurrent")
        let movedExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label == %@", "第 3 章：Chapter Three，开始于 2:00"
            ),
            object: currentRow
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [movedExpectation], timeout: 10),
            .completed,
            "current-chapter indicator must move to row 2, got \(currentRow.exists ? currentRow.label : "missing")"
        )
        attachScreenshot(app, name: "P2-chapter-jumped")

        // Current time must reflect the jump past 2:00.
        let currentLabel = element(app, "currentTimeText")
        reveal(currentLabel, in: app)
        var reached = false
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let secs = seconds(from: currentLabel.label), secs >= 120 {
                reached = true
                break
            }
            usleep(300_000)
        }
        XCTAssertTrue(
            reached,
            "current time never reached 2:00, got \(currentLabel.label)"
        )
    }
}
