import XCTest

/// English-language coverage for the app and LocalPodKit display names.
/// Every launch here is pinned to en/en_US; the other suites are pinned to
/// zh-Hans by `launchPinned()`'s default.
@MainActor
final class M5LocalizationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingAndMainTabsAreEnglish() throws {
        let app = makeApp(
            ["--m0-reset-data", "--m5-show-onboarding"],
            locale: UITestLocale.english
        )

        let screen = element(app, "onboardingScreen")
        XCTAssertTrue(
            screen.waitForExistence(timeout: 20),
            "Forced onboarding did not appear"
        )
        XCTAssertTrue(
            app.staticTexts["Welcome to LocalPod"].waitForExistence(timeout: 10),
            "Onboarding hero must be in English"
        )
        XCTAssertTrue(
            app.staticTexts["Folder imports scan recursively"].waitForExistence(timeout: 10),
            "Localized onboarding feature copy is missing"
        )

        let continueButton = element(app, "onboardingContinueButton")
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        XCTAssertEqual(continueButton.label, "Get Started")
        continueButton.tap()
        waitForDisappearance(screen, timeout: 10)

        for tab in ["Library", "Import", "Playback", "Inbox", "Diagnostics"] {
            let button = app.buttons[tab].firstMatch
            XCTAssertTrue(
                button.waitForExistence(timeout: 20),
                "Missing English tab \(tab)"
            )
        }
        XCTAssertFalse(
            app.buttons["资料库"].firstMatch.exists,
            "Chinese tab labels must not leak into English mode"
        )
        attach(app, name: "M5-localization-english-tabs")
    }

    func testEnglishSettingsAndPlaybackAccessibility() throws {
        let app = makeApp(
            [
                "--m0-reset-data",
                "--m5-skip-onboarding",
                "--m3-open-settings",
                "--m2-auto-play-long-audio",
                "--m2-no-autoplay"
            ],
            locale: UITestLocale.english
        )

        let close = element(app, "settingsCloseButton")
        XCTAssertTrue(
            close.waitForExistence(timeout: 20),
            "Settings sheet did not open"
        )
        XCTAssertEqual(close.label, "Done")
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 10),
            "Settings navigation title must be English"
        )
        XCTAssertTrue(
            app.staticTexts["Default Speed"].waitForExistence(timeout: 10),
            "Settings labels must be English"
        )
        attach(app, name: "M5-localization-english-settings")
        close.tap()
        waitForDisappearance(close, timeout: 10)

        tapTab("Playback", in: app)

        let title = element(app, "currentPlaybackTitle")
        reveal(title, in: app)
        XCTAssertEqual(title.label, "Long Audio Test")

        let previous = element(app, "previousTrackButton")
        reveal(previous, in: app)
        XCTAssertEqual(previous.label, "Previous")

        let playPause = element(app, "playPauseButton")
        reveal(playPause, in: app)
        XCTAssertTrue(
            ["Play", "Pause"].contains(playPause.label),
            "unexpected play/pause label \(playPause.label)"
        )

        let skipBackward = element(app, "skipBackwardButton")
        reveal(skipBackward, in: app)
        XCTAssertTrue(
            skipBackward.label.contains("Rewind"),
            "unexpected skip-backward label \(skipBackward.label)"
        )

        let skipForward = element(app, "skipForwardButton")
        reveal(skipForward, in: app)
        XCTAssertTrue(
            skipForward.label.contains("Forward"),
            "unexpected skip-forward label \(skipForward.label)"
        )

        let next = element(app, "nextTrackButton")
        reveal(next, in: app)
        XCTAssertEqual(next.label, "Next")

        let slider = element(app, "playbackSlider")
        reveal(slider, in: app)
        XCTAssertEqual(slider.label, "Playback Progress")

        let shuffle = element(app, "queueShuffleButton")
        reveal(shuffle, in: app)
        XCTAssertEqual(shuffle.label, "Shuffle")

        // This value comes from LocalPodKit's QueueRepeatMode.displayName.
        let repeatMode = element(app, "queueRepeatButton")
        reveal(repeatMode, in: app)
        let repeatValue = String(describing: repeatMode.value ?? "")
        XCTAssertTrue(
            ["Repeat Off", "Repeat All", "Repeat One"].contains(repeatValue),
            "unexpected LocalPodKit repeat-mode value \(repeatValue)"
        )

        let clear = element(app, "queueClearButton")
        reveal(clear, in: app)
        XCTAssertEqual(clear.label, "Clear Queue")

        let phase = element(app, "playbackPhaseText")
        let englishPhases = [
            "Not Playing", "Loading", "Ready", "Playing",
            "Paused", "Buffering", "Interrupted", "Playback Ended", "Playback Failed"
        ]
        let phaseExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "exists == true AND label IN %@",
                englishPhases
            ),
            object: phase
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [phaseExpectation], timeout: 15),
            .completed,
            "Playback phase must use a LocalPodKit English display name; got \(phase.label)"
        )
        attach(app, name: "M5-localization-english-playback")
    }

    func testEnglishSampleImportShowsLocalizedKitSourceName() throws {
        let app = makeApp(
            ["--m0-reset-data", "--m5-skip-onboarding"],
            locale: UITestLocale.english
        )

        tapTab("Import", in: app)
        let addButton = element(app, "sampleAddButton")
        XCTAssertTrue(addButton.waitForExistence(timeout: 20))
        XCTAssertEqual(addButton.label, "Add Sample Content")
        addButton.tap()

        let summary = waitForLabel(
            app,
            identifier: "importCategorySummary",
            contains: "Imported 3",
            timeout: 60
        )
        XCTAssertTrue(
            summary.label.contains("Duplicates 0"),
            "unexpected English summary \(summary.label)"
        )

        tapTab("Library", in: app)
        let stats = waitForLabel(
            app,
            identifier: "libraryStatsText",
            contains: "3 items",
            timeout: 20
        )
        XCTAssertTrue(stats.label.contains("3 items"))

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "libraryItem-"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()

        // `MediaSource.displayName` is produced by LocalPodKit; the collection
        // name and file names are user data and intentionally stay Chinese.
        let sourceValue = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Sample"))
            .firstMatch
        XCTAssertTrue(
            sourceValue.waitForExistence(timeout: 10),
            "Sample source must be the English LocalPodKit display name"
        )
        XCTAssertTrue(
            sourceValue.label.contains("Sample"),
            "Sample source must be the English LocalPodKit display name"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "示例内容"))
                .firstMatch
                .waitForExistence(timeout: 10),
            "The sample collection name is user data and must stay as created"
        )
        attach(app, name: "M5-localization-english-sample-detail")
    }

    // MARK: - Helpers

    private func makeApp(_ arguments: [String], locale: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchPinned(locale)
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func tapTab(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Missing tab \(label)")
        button.tap()
    }

    private func waitForLabel(
        _ app: XCUIApplication,
        identifier: String,
        contains text: String,
        timeout: TimeInterval = 60
    ) -> XCUIElement {
        let element = element(app, identifier)
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(identifier)")
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text),
            object: element
        )
        wait(for: [expectation], timeout: timeout)
        return element
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
            app.swipeUp()
            attempts += 1
        }
        if element.exists && element.isHittable { return }

        var resets = 0
        while !(element.exists && element.isHittable), resets < 8 {
            app.swipeDown()
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

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
