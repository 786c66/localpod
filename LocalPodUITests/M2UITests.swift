import XCTest

@MainActor
final class M2UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSpeedPresetsPlayPauseAndSkip() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--m0-reset-data",
            "--m2-auto-play-long-audio",
            "--m2-no-autoplay"
        ]
        app.launchPinned()

        let title = app.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertEqual(title.label, "长音频测试")

        let playPause = app.descendants(matching: .any)["playPauseButton"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 20))
        waitForLabel(playPause, equals: "播放", timeout: 20)

        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        reveal(playPause, in: app)
        playPause.tap()
        waitForLabel(playPause, equals: "暂停", timeout: 10)

        let rateText = app.descendants(matching: .any)["playbackRateText"]
        XCTAssertTrue(rateText.waitForExistence(timeout: 10))

        let presets: [(identifier: String, label: String)] = [
            ("speedOption-0.5", "0.5×"),
            ("speedOption-1.0", "1.0×"),
            ("speedOption-1.5", "1.5×"),
            ("speedOption-2.0", "2.0×"),
            ("speedOption-2.5", "2.5×"),
            ("speedOption-3.0", "3.0×")
        ]
        for preset in presets {
            tapSpeedChip(preset.identifier, in: app)
            waitForLabelContains(rateText, text: preset.label, timeout: 5)
        }

        let time = app.descendants(matching: .any)["currentTimeText"]
        XCTAssertTrue(time.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(
            seconds(from: time.label),
            0,
            "playback time did not advance while selecting speeds"
        )

        playPause.tap()
        waitForLabel(playPause, equals: "播放", timeout: 10)
        attachScreenshot(app, name: "M2-speed-and-controls")
    }

    /// 改了倍速、杀掉 App 重开又变回 1×. The speed chips now write through
    /// PlaybackSession into AppSettingsStore, and attach re-applies the saved
    /// speed, so the second launch must come up at the chosen 2.0×.
    func testSpeedPersistsAcrossRelaunch() throws {
        let first = XCUIApplication()
        first.launchArguments = [
            "--m0-reset-data",
            "--m2-auto-play-long-audio",
            "--m2-no-autoplay"
        ]
        first.launchPinned()

        let firstRate = first.descendants(matching: .any)["playbackRateText"]
        XCTAssertTrue(firstRate.waitForExistence(timeout: 20))
        waitForLabelContains(firstRate, text: "1.0×", timeout: 5)

        tapSpeedChip("speedOption-2.0", in: first)
        waitForLabelContains(firstRate, text: "2.0×", timeout: 5)
        first.terminate()

        let second = XCUIApplication()
        second.launchArguments = [
            "--m2-auto-play-long-audio",
            "--m2-no-autoplay"
        ]
        second.launchPinned()

        let secondTitle = second.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(secondTitle.waitForExistence(timeout: 20))
        let secondRate = second.descendants(matching: .any)["playbackRateText"]
        XCTAssertTrue(secondRate.waitForExistence(timeout: 10))
        waitForLabelContains(secondRate, text: "2.0×", timeout: 5)
        attachScreenshot(second, name: "M2-speed-restored")
    }

    /// The owner's cold-launch repro: kill the app with a queue persisted,
    /// reopen, switch to the player. A transient category-pin failure used to
    /// be reported one-shot, landing after the restored item loaded, and the
    /// player page showed the "音频会话激活失败" banner even though audio
    /// then played fine. The seam fails the first pin attempt; the retry must
    /// absorb it silently and playback must still start.
    func testColdLaunchTransientAudioSessionFailureShowsNoBanner() throws {
        let first = XCUIApplication()
        first.launchArguments = [
            "--m0-reset-data",
            "--m3-seed-playable-library",
            "--m3-seed-queue",
            "--m3-auto-play-first"
        ]
        first.launchPinned()
        let seededTitle = first.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(seededTitle.waitForExistence(timeout: 20))
        first.terminate()

        let second = XCUIApplication()
        second.launchArguments = ["--m2-simulate-audio-session-failure"]
        second.launchPinned()

        // Land on the player page the way a user does — via the tab bar.
        let playTab = second.buttons["播放"].firstMatch
        XCTAssertTrue(playTab.waitForExistence(timeout: 20))
        playTab.tap()

        let restoredTitle = second.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(restoredTitle.waitForExistence(timeout: 20))
        XCTAssertEqual(restoredTitle.label, "队列测试 A")

        // Give a late one-shot failure (the old behavior) time to land before
        // asserting it never became a banner.
        sleep(2)
        let banner = second.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "音频会话激活失败"))
            .firstMatch
        XCTAssertFalse(
            banner.exists,
            "transient audio-session pin failures must not surface as a banner"
        )
        XCTAssertFalse(
            second.descendants(matching: .any)["playbackRetryButton"].exists,
            "no retry row should appear for a transient audio-session failure"
        )

        // The retry must not hurt real playback: the restored item still plays.
        let playPause = second.descendants(matching: .any)["playPauseButton"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        waitForLabel(playPause, equals: "播放", timeout: 10)
        reveal(playPause, in: second)
        playPause.tap()
        waitForLabel(playPause, equals: "暂停", timeout: 10)
        attachScreenshot(second, name: "M2-no-audio-session-banner")
    }

    /// The regression the owner hit on device: dragging the progress bar did
    /// nothing. The scrubber is one real Slider; this test drives it the way
    /// a finger does — press on the bar, drag to another fraction, release —
    /// and requires the position to move to (and stay at) the dragged spot.
    /// Paused first so the assertion compares against a still clock.
    func testScrubberDragChangesPosition() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--m0-reset-data",
            "--m2-auto-play-long-audio",
            "--m2-no-autoplay",
            "--m2-seek-to", "30"
        ]
        app.launchPinned()

        let playPause = app.descendants(matching: .any)["playPauseButton"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 20))
        waitForLabel(playPause, equals: "播放", timeout: 20)

        let slider = app.descendants(matching: .any)["playbackSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        reveal(slider, in: app)
        let sliderFrame = slider.frame
        // The Slider is hittable and owns its 44 pt band; assert the touch
        // really lands on it before dragging.
        XCTAssertTrue(slider.isHittable, "playback slider must be hittable")

        let time = app.descendants(matching: .any)["currentTimeText"]
        XCTAssertTrue(time.waitForExistence(timeout: 10))
        let before = seconds(from: time.label)
        XCTAssertEqual(before, 30, accuracy: 3)

        // Drag from ~15% to ~85% of the bar, then give the seek a moment.
        let startX = sliderFrame.minX + sliderFrame.width * 0.15
        let endX = sliderFrame.minX + sliderFrame.width * 0.85
        let startY = sliderFrame.midY
        let start = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        ).withOffset(CGVector(dx: startX, dy: startY))
        let end = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        ).withOffset(CGVector(dx: endX, dy: startY))
        start.press(forDuration: 0.1, thenDragTo: end)

        // The position must land near the dragged fraction (85% of 298s ≈
        // 253s) — this is the proof the drag actually worked.
        let dragged = NSPredicate(
            format: "label IN %@", ["4:07", "4:08", "4:09", "4:10", "4:11", "4:12", "4:13"]
        )
        let draggedExpectation = XCTNSPredicateExpectation(
            predicate: dragged,
            object: time
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [draggedExpectation], timeout: 10),
            .completed,
            "dragging the scrubber must move playback to ~4:09, got \(time.label)"
        )
        // The position must stay: one seek on release, not a spring-back.
        sleep(2)
        XCTAssertGreaterThanOrEqual(
            seconds(from: time.label),
            245,
            "position sprang back after the drag: \(time.label)"
        )
        attachScreenshot(app, name: "M2-scrubber-dragged")
    }

    func testResumeAfterRelaunchWithinTwoSeconds() throws {
        let first = XCUIApplication()
        first.launchArguments = [
            "--m0-reset-data",
            "--m2-auto-play-long-audio",
            "--m2-no-autoplay",
            "--m2-seek-to", "120"
        ]
        first.launchPinned()

        let firstTitle = first.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(firstTitle.waitForExistence(timeout: 20))
        let firstPlayPause = first.descendants(matching: .any)["playPauseButton"]
        // Loaded paused: the button offers 播放.
        waitForLabel(firstPlayPause, equals: "播放", timeout: 20)
        let firstTime = first.descendants(matching: .any)["currentTimeText"]
        XCTAssertTrue(firstTime.waitForExistence(timeout: 10))
        XCTAssertEqual(Double(seconds(from: firstTime.label)), 120, accuracy: 2)
        first.terminate()

        let second = XCUIApplication()
        second.launchArguments = [
            "--m2-auto-play-long-audio",
            "--m2-no-autoplay"
        ]
        second.launchPinned()

        let secondTitle = second.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(secondTitle.waitForExistence(timeout: 20))
        let secondPlayPause = second.descendants(matching: .any)["playPauseButton"]
        waitForLabel(secondPlayPause, equals: "播放", timeout: 20)
        let secondTime = second.descendants(matching: .any)["currentTimeText"]
        XCTAssertTrue(secondTime.waitForExistence(timeout: 10))
        XCTAssertEqual(
            Double(seconds(from: secondTime.label)),
            120,
            accuracy: 2,
            "resume position \(secondTime.label) differs from saved 2:00"
        )
        attachScreenshot(second, name: "M2-resume-after-relaunch")
    }

    func testFinishedItemDoesNotAutoResume() throws {
        let first = XCUIApplication()
        first.launchArguments = [
            "--m0-reset-data",
            "--m2-auto-play-long-audio",
            "--m2-seek-to", "297.5"
        ]
        first.launchPinned()

        let title = first.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        // The fixture is 298 s and the seek is 297.5 s: playback runs to the
        // end within seconds, which shows up as the play button flipping to
        // 播放 after starting as 暂停.
        let firstPlayPause = first.descendants(matching: .any)["playPauseButton"]
        waitForLabel(firstPlayPause, equals: "播放", timeout: 30)
        first.terminate()

        let second = XCUIApplication()
        second.launchArguments = [
            "--m2-auto-play-long-audio",
            "--m2-no-autoplay"
        ]
        second.launchPinned()

        let secondTitle = second.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(secondTitle.waitForExistence(timeout: 20))
        let secondPlayPause = second.descendants(matching: .any)["playPauseButton"]
        waitForLabel(secondPlayPause, equals: "播放", timeout: 20)
        let secondTime = second.descendants(matching: .any)["currentTimeText"]
        XCTAssertTrue(secondTime.waitForExistence(timeout: 10))
        XCTAssertEqual(
            Double(seconds(from: secondTime.label)),
            0,
            accuracy: 2,
            "finished item should restart at 0:00, got \(secondTime.label)"
        )
        attachScreenshot(second, name: "M2-finished-restarts-at-zero")
    }

    func testForceQuitWhilePlayingResumesWithinTwoSeconds() throws {
        let first = XCUIApplication()
        first.launchArguments = [
            "--m0-reset-data",
            "--m2-auto-play-long-audio"
        ]
        first.launchPinned()

        let title = first.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        // Auto-play from launch: the button offers 暂停 while playing.
        let firstPlayPause = first.descendants(matching: .any)["playPauseButton"]
        waitForLabel(firstPlayPause, equals: "暂停", timeout: 20)
        let time = first.descendants(matching: .any)["currentTimeText"]
        XCTAssertTrue(time.waitForExistence(timeout: 10))
        sleep(3)
        let beforeKill = seconds(from: time.label)
        XCTAssertGreaterThan(beforeKill, 0)
        first.terminate()

        let second = XCUIApplication()
        second.launchArguments = [
            "--m2-auto-play-long-audio",
            "--m2-no-autoplay"
        ]
        second.launchPinned()

        let secondTitle = second.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(secondTitle.waitForExistence(timeout: 20))
        let secondPlayPause = second.descendants(matching: .any)["playPauseButton"]
        waitForLabel(secondPlayPause, equals: "播放", timeout: 20)
        let secondTime = second.descendants(matching: .any)["currentTimeText"]
        XCTAssertTrue(secondTime.waitForExistence(timeout: 10))
        let resumed = seconds(from: secondTime.label)
        XCTAssertEqual(
            Double(resumed),
            Double(beforeKill),
            accuracy: 2,
            "force-quit resume \(resumed)s differs from \(beforeKill)s by more than 2s"
        )
    }

    func testAudioAdvancesWhileAppIsInBackground() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--m0-reset-data",
            "--m2-auto-play-long-audio"
        ]
        app.launchPinned()

        let title = app.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        let playPause = app.descendants(matching: .any)["playPauseButton"]
        waitForLabel(playPause, equals: "暂停", timeout: 20)
        let time = app.descendants(matching: .any)["currentTimeText"]
        XCTAssertTrue(time.waitForExistence(timeout: 10))
        let before = seconds(from: time.label)

        XCUIDevice.shared.press(.home)
        sleep(3)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        waitForLabel(playPause, equals: "暂停", timeout: 10)

        let after = seconds(from: time.label)
        XCTAssertGreaterThanOrEqual(
            after - before,
            2,
            "audio did not advance in background: \(before)s -> \(after)s"
        )
        attachScreenshot(app, name: "M2-audio-after-background")
    }

    // MARK: - Helpers

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !element.isHittable, attempts < 4 {
            app.swipeUp()
            attempts += 1
        }
    }

    /// Nine presets no longer fit on a phone: the chip row scrolls
    /// horizontally, so swipe on a visible chip until the target is hittable.
    /// The row can also sit below the fold (the player card grew wider
    /// spacing), so scroll the List up first when no chip is on screen.
    private func tapSpeedChip(_ identifier: String, in app: XCUIApplication) {
        let chip = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "Missing \(identifier)")
        let rates = ["0.5", "0.8", "1.0", "1.2", "1.5", "1.8", "2.0", "2.5", "3.0"]

        func hittableAnchor() -> XCUIElement? {
            rates
                .map { app.descendants(matching: .any)["speedOption-\($0)"] }
                .first { $0.exists && $0.isHittable }
        }

        var vertical = 0
        var horizontal = 0
        while !chip.isHittable, vertical + horizontal < 12 {
            if let anchor = hittableAnchor() {
                anchor.swipeLeft()
                horizontal += 1
            } else if vertical < 6 {
                swipeListUp(in: app)
                vertical += 1
            } else {
                break
            }
        }
        XCTAssertTrue(chip.isHittable, "\(identifier) did not become reachable")
        chip.tap()
    }

    /// The scrubber owns the window center; start list swipes low so the
    /// List scrolls instead of the scrubber eating the gesture.
    private func swipeListUp(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end)
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

    private func waitForLabelContains(
        _ element: XCUIElement,
        text: String,
        timeout: TimeInterval
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "expected label containing \(text), got \(element.label)"
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
}
