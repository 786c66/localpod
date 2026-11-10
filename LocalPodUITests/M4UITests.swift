import XCTest

@MainActor
final class M4UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeApp(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchPinned()
        return app
    }

    private func waitForLabel(
        _ app: XCUIApplication,
        identifier: String,
        contains text: String,
        timeout: TimeInterval = 60
    ) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(identifier)")
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text),
            object: element
        )
        wait(for: [expectation], timeout: timeout)
        return element
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testOpenInImportAndDedup() throws {
        let app = makeApp(["--m0-reset-data", "--m4-auto-open-in"])

        let firstSummary = waitForLabel(
            app,
            identifier: "inboxCategorySummary",
            contains: "导入 1",
            timeout: 60
        )
        XCTAssertTrue(firstSummary.label.contains("重复 0"))
        XCTAssertTrue(firstSummary.label.contains("失败 0"))
        let runReport = app.descendants(matching: .any)["inboxRunReportPath"]
        if !runReport.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(runReport.waitForExistence(timeout: 10))
        XCTAssertTrue(runReport.label.contains("-run-"))
        XCTAssertTrue(runReport.label.contains("ImportReports"))
        attach(app, name: "M4-open-in-imported")

        app.buttons["资料库"].tap()
        let stats = waitForLabel(app, identifier: "libraryStatsText", contains: "1 条", timeout: 20)
        XCTAssertTrue(stats.label.contains("1 条"))
        let rows = app.descendants(matching: .any)
            .matching(identifier: "libraryItem-demo-audio")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20))
        XCTAssertEqual(rows.count, 1, "Open-in must create exactly one library item")

        // Open-in is not the Finder inbox: the item must keep that source mark.
        rows.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["demo-audio"].waitForExistence(timeout: 10))
        let externalSource = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "外部打开"))
            .firstMatch
        XCTAssertTrue(
            externalSource.waitForExistence(timeout: 10),
            "Open-in imports must be marked as 外部打开"
        )
        attach(app, name: "M4-open-in-source-mark")
        app.terminate()

        // Same launch argument without reset: content dedup, no second item.
        app.launchArguments = ["--m4-auto-open-in"]
        app.launchPinned()
        let secondSummary = waitForLabel(
            app,
            identifier: "inboxCategorySummary",
            contains: "导入 0",
            timeout: 60
        )
        XCTAssertTrue(secondSummary.label.contains("重复 1"))
        XCTAssertTrue(secondSummary.label.contains("失败 0"))
        attach(app, name: "M4-open-in-dedup")

        app.buttons["资料库"].tap()
        let relaunchedStats = waitForLabel(
            app,
            identifier: "libraryStatsText",
            contains: "1 条",
            timeout: 20
        )
        XCTAssertTrue(relaunchedStats.label.contains("1 条"))
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifier: "libraryItem-demo-audio").count,
            1,
            "Relaunching with the same open-in file must not duplicate it"
        )
    }

    func testForegroundInboxWaitsForStableFile() throws {
        let app = makeApp(["--m0-reset-data", "--m4-foreground-write-inbox"])

        // The writer runs for ~5.6s; the watcher must see the file as pending
        // and unstable without importing it.
        let pending = waitForLabel(
            app,
            identifier: "inboxPendingCount",
            contains: "1",
            timeout: 20
        )
        XCTAssertTrue(pending.label.contains("1"))
        let stability = waitForLabel(
            app,
            identifier: "inboxStabilityText",
            contains: "1",
            timeout: 15
        )
        XCTAssertTrue(stability.label.contains("未稳定"))
        XCTAssertFalse(
            app.descendants(matching: .any)["inboxCategorySummary"].exists,
            "A growing inbox file must not be imported"
        )
        attach(app, name: "M4-foreground-file-growing")

        // Once the write finishes and the size is quiet, the watcher imports it
        // exactly once without leaving/returning to the app.
        let importedSummary = waitForLabel(
            app,
            identifier: "inboxCategorySummary",
            contains: "导入 1",
            timeout: 60
        )
        XCTAssertTrue(importedSummary.label.contains("失败 0"))
        let finalPending = waitForLabel(
            app,
            identifier: "inboxPendingCount",
            contains: "0",
            timeout: 30
        )
        XCTAssertTrue(finalPending.label.contains("待处理 0"))
        attach(app, name: "M4-foreground-imported")

        app.buttons["资料库"].tap()
        let stats = waitForLabel(app, identifier: "libraryStatsText", contains: "1 条", timeout: 20)
        XCTAssertTrue(stats.label.contains("1 条"))
        let rows = app.descendants(matching: .any)
            .matching(identifier: "libraryItem-SlowDrop")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20))
        XCTAssertEqual(rows.count, 1, "The slow drop must be imported exactly once")
    }

    func testUnsupportedInboxFileIsQuarantined() throws {
        let app = makeApp(["--m0-reset-data", "--m4-seed-unsupported-inbox"])

        let skipped = waitForLabel(
            app,
            identifier: "inboxSkippedCount",
            contains: "1",
            timeout: 30
        )
        XCTAssertTrue(skipped.label.contains("1"))
        let pending = waitForLabel(
            app,
            identifier: "inboxPendingCount",
            contains: "0",
            timeout: 20
        )
        XCTAssertTrue(pending.label.contains("待处理 0"))
        XCTAssertFalse(
            app.descendants(matching: .any)["inboxCategorySummary"].exists,
            "An unsupported inbox file must never enter an import run"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["inboxRetryButton"].exists,
            "Quarantining is not an import failure"
        )
        attach(app, name: "M4-unsupported-quarantined")

        app.buttons["资料库"].tap()
        let stats = waitForLabel(app, identifier: "libraryStatsText", contains: "0 条", timeout: 20)
        XCTAssertTrue(stats.label.contains("0 条"))

        // Relaunch without reset: .Skipped is hidden and must stay unimported.
        app.terminate()
        app.launchArguments = []
        app.launchPinned()
        let relaunchedStats = waitForLabel(
            app,
            identifier: "libraryStatsText",
            contains: "0 条",
            timeout: 20
        )
        XCTAssertTrue(relaunchedStats.label.contains("0 条"))

        app.buttons["收件箱"].tap()
        let relaunchedSkipped = waitForLabel(
            app,
            identifier: "inboxSkippedCount",
            contains: "1",
            timeout: 20
        )
        XCTAssertTrue(relaunchedSkipped.label.contains("1"))
        let relaunchedPending = waitForLabel(
            app,
            identifier: "inboxPendingCount",
            contains: "0",
            timeout: 20
        )
        XCTAssertTrue(relaunchedPending.label.contains("待处理 0"))
        XCTAssertFalse(
            app.descendants(matching: .any)["inboxCategorySummary"].exists,
            "The quarantined file must not be imported after relaunch"
        )
    }
}
