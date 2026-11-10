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
        app.launch()

        let title = app.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertEqual(title.label, "长音频测试")

        let phase = app.descendants(matching: .any)["playbackPhaseText"]
        XCTAssertTrue(phase.waitForExistence(timeout: 20))
        waitForLabel(phase, equals: "就绪", timeout: 20)

        let playPause = app.descendants(matching: .any)["playPauseButton"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        reveal(playPause, in: app)
        playPause.tap()
        waitForLabel(phase, equals: "播放中", timeout: 10)

        let rateText = app.descendants(matching: .any)["playbackRateText"]
        XCTAssertTrue(rateText.waitForExistence(timeout: 10))

        let presets: [(identifier: String, label: String)] = [
            ("speedOption-0.5", "0.5×"),
            ("speedOption-1.0", "1.0×"),
            ("speedOption-1.5", "1.5×"),
            ("speedOption-2.0", "2.0×"),
            ("speedOption-3.0", "3.0×"),
            ("speedOption-1.0", "1.0×")
        ]
        for preset in presets {
            let option = app.descendants(matching: .any)[preset.identifier]
            XCTAssertTrue(option.waitForExistence(timeout: 10))
            reveal(option, in: app)
            option.tap()
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
        waitForLabel(phase, equals: "已暂停", timeout: 10)
        attachScreenshot(app, name: "M2-speed-and-controls")
    }

    func testResumeAfterRelaunchWithinTwoSeconds() throws {
        let first = XCUIApplication()
        first.launchArguments = [
            "--m0-reset-data",
            "--m2-auto-play-long-audio",
            "--m2-no-autoplay",
            "--m2-seek-to", "120"
        ]
        first.launch()

        let firstTitle = first.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(firstTitle.waitForExistence(timeout: 20))
        let firstPhase = first.descendants(matching: .any)["playbackPhaseText"]
        waitForLabel(firstPhase, equals: "就绪", timeout: 20)
        let firstTime = first.descendants(matching: .any)["currentTimeText"]
        XCTAssertTrue(firstTime.waitForExistence(timeout: 10))
        XCTAssertEqual(Double(seconds(from: firstTime.label)), 120, accuracy: 2)
        first.terminate()

        let second = XCUIApplication()
        second.launchArguments = [
            "--m2-auto-play-long-audio",
            "--m2-no-autoplay"
        ]
        second.launch()

        let secondTitle = second.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(secondTitle.waitForExistence(timeout: 20))
        let secondPhase = second.descendants(matching: .any)["playbackPhaseText"]
        waitForLabel(secondPhase, equals: "就绪", timeout: 20)
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
        first.launch()

        let title = first.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        let phase = first.descendants(matching: .any)["playbackPhaseText"]
        waitForLabel(phase, equals: "播放结束", timeout: 30)
        first.terminate()

        let second = XCUIApplication()
        second.launchArguments = [
            "--m2-auto-play-long-audio",
            "--m2-no-autoplay"
        ]
        second.launch()

        let secondTitle = second.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(secondTitle.waitForExistence(timeout: 20))
        let secondPhase = second.descendants(matching: .any)["playbackPhaseText"]
        waitForLabel(secondPhase, equals: "就绪", timeout: 20)
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
        first.launch()

        let title = first.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        let phase = first.descendants(matching: .any)["playbackPhaseText"]
        waitForAnyLabel(phase, labels: ["播放中", "缓冲中"], timeout: 20)
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
        second.launch()

        let secondTitle = second.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(secondTitle.waitForExistence(timeout: 20))
        let secondPhase = second.descendants(matching: .any)["playbackPhaseText"]
        waitForLabel(secondPhase, equals: "就绪", timeout: 20)
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

    func testVideoFullScreenPresentAndDismiss() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--m0-reset-data", "--m0-auto-play-h264"]
        app.launch()

        let close = app.descendants(matching: .any)["closeVideoButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 20))
        attachScreenshot(app, name: "M2-video-fullscreen")

        close.tap()
        XCTAssertTrue(
            close.waitForNonExistence(timeout: 10),
            "video full-screen cover did not dismiss"
        )
    }

    func testAudioAdvancesWhileAppIsInBackground() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--m0-reset-data",
            "--m2-auto-play-long-audio"
        ]
        app.launch()

        let title = app.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        let phase = app.descendants(matching: .any)["playbackPhaseText"]
        waitForAnyLabel(phase, labels: ["播放中", "缓冲中"], timeout: 20)
        let time = app.descendants(matching: .any)["currentTimeText"]
        XCTAssertTrue(time.waitForExistence(timeout: 10))
        let before = seconds(from: time.label)

        XCUIDevice.shared.press(.home)
        sleep(3)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        waitForAnyLabel(phase, labels: ["播放中", "缓冲中"], timeout: 10)

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

    private func waitForAnyLabel(
        _ element: XCUIElement,
        labels: [String],
        timeout: TimeInterval
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label IN %@", labels),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "expected one of \(labels), got \(element.label)"
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
