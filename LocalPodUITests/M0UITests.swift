import XCTest

@MainActor
final class M0UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testImport100Files() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--m0-reset-data"]
        app.launch()
        app.buttons["导入"].tap()

        let importButton = app.descendants(matching: .any)["importDemoFolderButton"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 20))
        importButton.tap()

        let progressText = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "文件 100/100"))
            .firstMatch
        XCTAssertTrue(progressText.waitForExistence(timeout: 120))
        attachScreenshot(app, name: "M0-import-100-result")

        let resultText = app.descendants(matching: .any)["importCategorySummary"]
        XCTAssertTrue(resultText.waitForExistence(timeout: 20))
        XCTAssertTrue(resultText.label.contains("导入 100"))
    }

    func testAudioPlaybackFromLaunchArgument() throws {
        let playbackApp = XCUIApplication()
        playbackApp.launchArguments = ["--m0-reset-data", "--m0-auto-play-audio"]
        playbackApp.launch()

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
        app.launch()

        let benchmarkLink = app.descendants(matching: .any)["benchmarkLink"]
        XCTAssertTrue(benchmarkLink.waitForExistence(timeout: 20))
        benchmarkLink.tap()

        let insertButton = app.descendants(matching: .any)["benchmarkInsertButton"]
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
        app.launch()

        let result = app.descendants(matching: .any)["inboxCategorySummary"]
        XCTAssertTrue(result.waitForExistence(timeout: 40))
        XCTAssertTrue(result.label.contains("导入 1"))

        let pending = app.descendants(matching: .any)["inboxPendingCount"]
        XCTAssertTrue(pending.waitForExistence(timeout: 10))
        XCTAssertTrue(pending.label.contains("0"))
        attachScreenshot(app, name: "M0-inbox-imported-from-finder")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
