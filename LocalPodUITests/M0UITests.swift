import XCTest

@MainActor
final class M0UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testImport100Files() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--m0-reset-data"]
        app.launchPinned()
        // Import moved into Settings; demo material lives on Diagnostics.
        openDiagnostics(in: app)

        let importButton = app.descendants(matching: .any)["importDemoFolderButton"]
        reveal(importButton, in: app)
        XCTAssertTrue(importButton.waitForExistence(timeout: 20))
        importButton.tap()

        // Progress is transient and can be off screen by the time XCUITest
        // regains control, so assert the completed summary instead. Reopening
        // Diagnostics puts its top-of-page import status in view. Progress
        // and cancellation UI are covered by the M1 slow-copy tests.
        closeSettings(in: app)
        openDiagnostics(in: app)
        let resultText = app.descendants(matching: .any)["importCategorySummary"]
        XCTAssertTrue(resultText.waitForExistence(timeout: 120))
        XCTAssertTrue(resultText.label.contains("导入 100"))
        attachScreenshot(app, name: "M0-import-100-result")
    }

    func testAudioPlaybackFromLaunchArgument() throws {
        let playbackApp = XCUIApplication()
        playbackApp.launchArguments = ["--m0-reset-data", "--m0-auto-play-audio"]
        playbackApp.launchPinned()

        let title = playbackApp.descendants(matching: .any)["currentPlaybackTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertEqual(title.label, "自动播放音频")

        let playPause = playbackApp.descendants(matching: .any)["playPauseButton"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        attachScreenshot(playbackApp, name: "M0-audio-now-playing")
        playPause.tap()
    }

    func testBenchmarkInsertAndList() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--m0-reset-data", "--m0-auto-benchmark"]
        app.launchPinned()

        // --m0-auto-benchmark opens Settings → 诊断; the benchmark entry is a
        // row at the bottom of that (lazy) List.
        let benchmarkLink = app.descendants(matching: .any)["benchmarkLink"]
        reveal(benchmarkLink, in: app)
        XCTAssertTrue(benchmarkLink.waitForExistence(timeout: 20))
        benchmarkLink.tap()

        let insertButton = app.descendants(matching: .any)["benchmarkInsertButton"]
        reveal(insertButton, in: app)
        XCTAssertTrue(insertButton.waitForExistence(timeout: 20))
        insertButton.tap()

        let status = app.descendants(matching: .any)["benchmarkStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        let finishExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "插入完成"),
            object: status
        )
        wait(for: [finishExpectation], timeout: 60)
        attachScreenshot(app, name: "M0-benchmark-insert-finished")

        let listLink = app.descendants(matching: .any)["benchmarkListLink"]
        reveal(listLink, in: app)
        XCTAssertTrue(listLink.waitForExistence(timeout: 10))
        listLink.tap()

        let anyBenchmark = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Benchmark "))
            .firstMatch
        XCTAssertTrue(anyBenchmark.waitForExistence(timeout: 20))
        attachScreenshot(app, name: "M0-benchmark-5000-list")
        app.swipeUp()
        app.swipeUp()
    }

    func testInboxImportFromFinderPath() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--m0-reset-data",
            "--m0-seed-inbox",
            "--m0-auto-inbox"
        ]
        app.launchPinned()

        let result = app.descendants(matching: .any)["inboxCategorySummary"]
        XCTAssertTrue(result.waitForExistence(timeout: 40))
        XCTAssertTrue(result.label.contains("导入 1"))

        let pending = app.descendants(matching: .any)["inboxPendingCount"]
        XCTAssertTrue(pending.waitForExistence(timeout: 10))
        XCTAssertTrue(pending.label.contains("0"))
        attachScreenshot(app, name: "M0-inbox-imported-from-finder")
    }

    private func openDiagnostics(in app: XCUIApplication) {
        let settings = app.descendants(matching: .any)["librarySettingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20), "Missing library settings entry")
        settings.tap()
        let link = app.descendants(matching: .any)["settingsDiagnosticsLink"]
        reveal(link, in: app)
        link.tap()
        XCTAssertTrue(
            app.navigationBars["诊断"].waitForExistence(timeout: 20),
            "Diagnostics page did not open"
        )
    }

    private func closeSettings(in app: XCUIApplication) {
        let close = app.descendants(matching: .any)["settingsCloseButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Missing settings Done button")
        close.tap()
    }

    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 16
    ) {
        var attempts = 0
        while !(element.exists && element.isHittable), attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(
            element.waitForExistence(timeout: 5),
            "Missing element \(element) after scrolling"
        )
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
