import XCTest

@MainActor
final class M5UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // XCTest runs UI-test teardown on the main thread, but the override is
        // nonisolated; assert the actor so XCUIDevice can be mutated without
        // an isolation warning.
        MainActor.assumeIsolated {
            XCUIDevice.shared.appearance = .light
        }
    }

    // MARK: - Onboarding

    func testOnboardingShowsOnceAndContinuePersists() throws {
        let app = makeApp(["--m5-reset-onboarding"])

        let screen = element(app, "onboardingScreen")
        XCTAssertTrue(
            screen.waitForExistence(timeout: 20),
            "First-run onboarding did not appear"
        )
        XCTAssertTrue(element(app, "onboardingContinueButton").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "onboardingImportButton").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "onboardingSkipButton").waitForExistence(timeout: 10))
        attach(app, name: "M5-onboarding")

        let continueButton = element(app, "onboardingContinueButton")
        continueButton.tap()
        waitForDisappearance(screen, timeout: 10)

        app.terminate()
        let relaunched = makeApp([])
        XCTAssertTrue(
            relaunched.buttons["资料库"].firstMatch.waitForExistence(timeout: 20),
            "Relaunch did not reach the main tab UI"
        )
        XCTAssertFalse(
            element(relaunched, "onboardingScreen").waitForExistence(timeout: 3),
            "Onboarding must not reappear after it was completed"
        )
    }

    func testShowOnboardingLaunchArgumentForcesSheet() throws {
        // --m0-reset-data marks onboarding complete for the M0-M4 suites;
        // --m5-show-onboarding must still force the sheet on top of that.
        let app = makeApp(["--m0-reset-data", "--m5-show-onboarding"])

        let screen = element(app, "onboardingScreen")
        XCTAssertTrue(
            screen.waitForExistence(timeout: 20),
            "--m5-show-onboarding did not force the onboarding sheet"
        )
        let skip = element(app, "onboardingSkipButton")
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()
        waitForDisappearance(screen, timeout: 10)
    }

    // MARK: - Empty states

    func testEmptyInboxAndImportStates() throws {
        let app = makeApp(["--m0-reset-data", "--m5-skip-onboarding"])
        openSettingsLink("settingsInboxLink", in: app)

        let inboxEmpty = element(app, "inboxEmptyState")
        XCTAssertTrue(
            inboxEmpty.waitForExistence(timeout: 20),
            "Empty inbox should show ContentUnavailableView"
        )
        let pending = element(app, "inboxPendingCount")
        XCTAssertTrue(pending.waitForExistence(timeout: 10))
        XCTAssertTrue(pending.label.contains("0"), "unexpected pending label \(pending.label)")
        attach(app, name: "M5-empty-inbox")

        // Back to the Settings root, then into the import page.
        element(app, "settingsCloseButton").tap()
        openSettingsLink("settingsImportLink", in: app)
        let recentEmpty = element(app, "importRecentEmptyState")
        reveal(recentEmpty, in: app)
        XCTAssertTrue(
            recentEmpty.waitForExistence(timeout: 20),
            "Recent-import section should show an empty state"
        )
    }

    func testPlaybackEmptyStateAction() throws {
        let app = makeApp(["--m0-reset-data", "--m5-skip-onboarding"])
        tapTab("播放", in: app)

        let empty = element(app, "playbackEmptyState")
        XCTAssertTrue(
            empty.waitForExistence(timeout: 20),
            "Playback should show an empty state when nothing is queued or loaded"
        )

        let goToLibrary = element(app, "playbackEmptyLibraryButton")
        reveal(goToLibrary, in: app)
        goToLibrary.tap()

        XCTAssertTrue(
            element(app, "libraryStatsText").waitForExistence(timeout: 15),
            "去资料库 should switch to the library tab"
        )
    }

    // MARK: - Accessibility

    func testPlaybackControlAccessibilityLabels() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m5-skip-onboarding",
            "--m2-auto-play-long-audio",
            "--m2-no-autoplay"
        ])

        let title = element(app, "currentPlaybackTitle")
        reveal(title, in: app)
        XCTAssertEqual(title.label, "长音频测试")

        let previous = element(app, "previousTrackButton")
        reveal(previous, in: app)
        XCTAssertEqual(previous.label, "上一首")

        let skipBackward = element(app, "skipBackwardButton")
        reveal(skipBackward, in: app)
        XCTAssertTrue(
            skipBackward.label.contains("快退"),
            "unexpected skip-backward label \(skipBackward.label)"
        )

        let playPause = element(app, "playPauseButton")
        reveal(playPause, in: app)
        XCTAssertFalse(playPause.label.isEmpty, "play/pause needs a non-empty label")
        XCTAssertTrue(
            ["播放", "暂停"].contains(playPause.label),
            "unexpected play/pause label \(playPause.label)"
        )

        let skipForward = element(app, "skipForwardButton")
        reveal(skipForward, in: app)
        XCTAssertTrue(
            skipForward.label.contains("快进"),
            "unexpected skip-forward label \(skipForward.label)"
        )

        let next = element(app, "nextTrackButton")
        reveal(next, in: app)
        XCTAssertEqual(next.label, "下一首")

        let slider = element(app, "playbackSlider")
        reveal(slider, in: app)
        XCTAssertEqual(slider.label, "播放进度")
        XCTAssertFalse(
            String(describing: slider.value ?? "").isEmpty,
            "progress slider needs an accessibility value"
        )

        let speed = element(app, "speedOption-1.0")
        reveal(speed, in: app)
        revealSpeedChip("speedOption-1.0", in: app)
        XCTAssertTrue(
            speed.label.contains("1.0×"),
            "unexpected speed chip label \(speed.label)"
        )

        // The queue is a bottom panel now: the expand button opens a sheet
        // whose header carries shuffle / repeat / clear.
        let expand = element(app, "queueExpandButton")
        reveal(expand, in: app)
        expand.tap()
        let shuffle = element(app, "queueShuffleButton")
        reveal(shuffle, in: app)
        XCTAssertEqual(shuffle.label, "随机播放")

        let repeatMode = element(app, "queueRepeatButton")
        reveal(repeatMode, in: app)
        XCTAssertEqual(repeatMode.label, "循环模式")

        let clear = element(app, "queueClearButton")
        reveal(clear, in: app)
        XCTAssertEqual(clear.label, "清空队列")
    }

    func testAccessibilityXXXLControlsRemainHittable() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m5-skip-onboarding",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
            "--m2-auto-play-long-audio",
            "--m2-no-autoplay"
        ])

        let title = element(app, "currentPlaybackTitle")
        reveal(title, in: app)
        XCTAssertEqual(title.label, "长音频测试")

        let playPause = element(app, "playPauseButton")
        reveal(playPause, in: app)
        XCTAssertTrue(playPause.isHittable, "play/pause must stay hittable at XXXL")
        XCTAssertTrue(
            ["播放", "暂停"].contains(playPause.label),
            "unexpected play/pause label \(playPause.label)"
        )

        let skipForward = element(app, "skipForwardButton")
        reveal(skipForward, in: app)
        XCTAssertTrue(skipForward.isHittable, "skip-forward must stay hittable at XXXL")

        let speed = element(app, "speedOption-1.0")
        reveal(speed, in: app)
        revealSpeedChip("speedOption-1.0", in: app)
        XCTAssertTrue(speed.isHittable, "speed chips must stay reachable at XXXL")
        attach(app, name: "M5-accessibility-xxxl")

        // The queue header becomes a wrapping/scrollable group at
        // accessibility sizes; its first action must still be reachable.
        let expand = element(app, "queueExpandButton")
        reveal(expand, in: app)
        expand.tap()
        let shuffle = element(app, "queueShuffleButton")
        reveal(shuffle, in: app)
        XCTAssertTrue(shuffle.isHittable, "queue actions must stay reachable at XXXL")
    }

    func testDarkModeScreenshot() throws {
        // This simulator runtime does not propagate XCUIDevice.appearance (or
        // simctl ui appearance) into the app's trait collection, so the
        // screenshot would render light despite the device setting. Keep the
        // real appearance switch and restore it afterwards, and use the
        // DEBUG-only launch seam to make SwiftUI resolve the dark palette for
        // this capture. Runtime builds do not force a color scheme.
        XCUIDevice.shared.appearance = .dark
        addTeardownBlock {
            XCUIDevice.shared.appearance = .light
        }

        let app = makeApp([
            "--m0-reset-data",
            "--m5-skip-onboarding",
            "--m5-force-dark-appearance",
            "--m2-auto-play-long-audio",
            "--m2-no-autoplay"
        ])

        let title = element(app, "currentPlaybackTitle")
        reveal(title, in: app)
        XCTAssertEqual(title.label, "长音频测试")
        XCTAssertTrue(element(app, "playPauseButton").waitForExistence(timeout: 10))
        attach(app, name: "M5-dark-mode")
    }

    // MARK: - Helpers

    private func makeApp(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchPinned()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Match the existing M0-M4 suites: SwiftUI on this iOS runtime exposes
    /// tab items as buttons by their visible label, not through `XCUIElement.tabBars`.
    /// Open Settings from the library gear and push one of its destinations.
    private func openSettingsLink(_ identifier: String, in app: XCUIApplication) {
        let settings = element(app, "librarySettingsButton")
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let link = element(app, identifier)
        reveal(link, in: app)
        link.tap()
    }

    private func tapTab(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Missing tab \(label)")
        button.tap()
    }

    /// The speed row scrolls horizontally once all nine presets are shown,
    /// and it can also sit below the fold; scroll up when no chip is on
    /// screen, then swipe on a visible chip.
    private func revealSpeedChip(_ identifier: String, in app: XCUIApplication) {
        let chip = element(app, identifier)
        let rates = ["0.5", "0.8", "1.0", "1.2", "1.5", "1.8", "2.0", "2.5", "3.0"]

        func hittableAnchor() -> XCUIElement? {
            rates
                .map { element(app, "speedOption-\($0)") }
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
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Element \(element) did not disappear"
        )
    }

    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 16
    ) {
        if element.exists && element.isHittable { return }

        var attempts = 0
        while !(element.exists && element.isHittable), attempts < maxSwipes {
            swipeListUp(in: app)
            attempts += 1
        }
        if element.exists && element.isHittable { return }

        var resets = 0
        while !(element.exists && element.isHittable), resets < 8 {
            swipeListDown(in: app)
            resets += 1
        }

        XCTAssertTrue(
            element.waitForExistence(timeout: 2),
            "Missing element \(element) after scrolling"
        )
        XCTAssertTrue(
            element.isHittable,
            "Element \(element) is not hittable after scrolling"
        )
    }

    /// The progress scrubber's DragGesture covers the window center on the
    /// playback screen; start swipes below it so the List scrolls.
    private func swipeListUp(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func swipeListDown(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
