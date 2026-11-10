import XCTest

@MainActor
final class M5DeliveryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Sample import

    func testAddSamplesShowsThreeItemsWithProvenanceAndSummary() throws {
        let app = makeApp(["--m0-reset-data", "--m5-skip-onboarding"])
        tapTab("导入", in: app)

        let addButton = element(app, "sampleAddButton")
        XCTAssertTrue(addButton.waitForExistence(timeout: 20))
        XCTAssertTrue(addButton.isEnabled, "sampleAddButton should be enabled")
        addButton.tap()

        let summary = waitForLabel(
            app,
            identifier: "importCategorySummary",
            contains: "导入 3",
            timeout: 60
        )
        XCTAssertTrue(summary.label.contains("重复 0"), "unexpected summary \(summary.label)")
        XCTAssertTrue(summary.label.contains("不支持 0"), "unexpected summary \(summary.label)")
        XCTAssertTrue(summary.label.contains("失败 0"), "unexpected summary \(summary.label)")
        let progress = element(app, "importProgressText")
        reveal(progress, in: app)
        XCTAssertTrue(progress.label.contains("文件 3/3"))
        attach(app, name: "M5-sample-import-summary")

        tapTab("资料库", in: app)
        let stats = waitForLabel(
            app,
            identifier: "libraryStatsText",
            contains: "3 条",
            timeout: 20
        )
        XCTAssertTrue(stats.label.contains("3 条"))
        let rows = libraryRows(in: app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20))
        attach(app, name: "M5-sample-library")

        rows.firstMatch.tap()
        let source = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "示例"))
            .firstMatch
        XCTAssertTrue(
            source.waitForExistence(timeout: 10),
            "Sample items must be marked with the 示例 source"
        )
        let collection = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "示例内容"))
            .firstMatch
        XCTAssertTrue(
            collection.waitForExistence(timeout: 10),
            "Sample items must belong to the 示例内容 collection"
        )
        attach(app, name: "M5-sample-detail")
    }

    // MARK: - Delete and re-add

    func testSettingsDeletesSamplesAndReAddRestoresThem() throws {
        let app = makeApp(["--m0-reset-data", "--m5-skip-onboarding"])
        addSamples(in: app)
        tapTab("资料库", in: app)
        _ = waitForLabel(app, identifier: "libraryStatsText", contains: "3 条", timeout: 20)

        openSettings(in: app)
        let countElement = element(app, "sampleCountText")
        reveal(countElement, in: app)
        let count = waitForLabel(
            app,
            identifier: "sampleCountText",
            contains: "3",
            timeout: 20
        )
        XCTAssertTrue(count.label.contains("3"), "unexpected sample count \(count.label)")

        let deleteButton = element(app, "sampleDeleteButton")
        reveal(deleteButton, in: app)
        XCTAssertTrue(deleteButton.isEnabled)
        deleteButton.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "Missing delete confirmation")
        let confirm = alert.buttons["删除"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()

        let clearedElement = element(app, "sampleCountText")
        reveal(clearedElement, in: app)
        let clearedCount = waitForLabel(
            app,
            identifier: "sampleCountText",
            contains: "0",
            timeout: 20
        )
        XCTAssertTrue(clearedCount.label.contains("0"), "unexpected sample count \(clearedCount.label)")
        let deleteSummary = element(app, "sampleDeleteSummary")
        reveal(deleteSummary, in: app)
        XCTAssertTrue(deleteSummary.label.contains("已删除 3"), "unexpected delete summary \(deleteSummary.label)")
        attach(app, name: "M5-sample-deleted")

        dismissSettings(in: app)

        let emptyStats = waitForLabel(
            app,
            identifier: "libraryStatsText",
            contains: "0 条",
            timeout: 20
        )
        XCTAssertTrue(emptyStats.label.contains("0 条"))
        XCTAssertEqual(libraryRows(in: app).count, 0, "Samples must disappear from the library")

        tapTab("导入", in: app)
        let addButton = element(app, "sampleAddButton")
        reveal(addButton, in: app)
        addButton.tap()

        tapTab("资料库", in: app)
        let restoredStats = waitForLabel(
            app,
            identifier: "libraryStatsText",
            contains: "3 条",
            timeout: 60
        )
        XCTAssertTrue(restoredStats.label.contains("3 条"))
        XCTAssertTrue(
            libraryRows(in: app).firstMatch.waitForExistence(timeout: 20),
            "Re-added samples should be visible in the library"
        )
        attach(app, name: "M5-sample-readded")
    }

    // MARK: - Dedup across relaunch

    func testRelaunchAddSamplesDeduplicatesWithoutGrowth() throws {
        let app = makeApp(["--m0-reset-data", "--m5-skip-onboarding"])
        addSamples(in: app)
        tapTab("资料库", in: app)
        _ = waitForLabel(app, identifier: "libraryStatsText", contains: "3 条", timeout: 20)
        XCTAssertTrue(libraryRows(in: app).firstMatch.waitForExistence(timeout: 20))
        app.terminate()

        let relaunched = makeApp(["--m5-skip-onboarding"])
        tapTab("导入", in: relaunched)
        let addButton = element(relaunched, "sampleAddButton")
        XCTAssertTrue(addButton.waitForExistence(timeout: 20))
        addButton.tap()

        let summary = waitForLabel(
            relaunched,
            identifier: "importCategorySummary",
            contains: "导入 0",
            timeout: 60
        )
        XCTAssertTrue(
            summary.label.contains("重复 3"),
            "Re-adding samples at relaunch must report 3 duplicates: \(summary.label)"
        )
        XCTAssertTrue(
            summary.label.contains("失败 0"),
            "unexpected summary \(summary.label)"
        )
        attach(relaunched, name: "M5-sample-dedup-relaunch")

        tapTab("资料库", in: relaunched)
        let stats = waitForLabel(
            relaunched,
            identifier: "libraryStatsText",
            contains: "3 条",
            timeout: 20
        )
        XCTAssertTrue(stats.label.contains("3 条"))
        XCTAssertTrue(
            libraryRows(in: relaunched).firstMatch.waitForExistence(timeout: 20),
            "Deduplicated samples should still be visible"
        )
    }

    // MARK: - Helpers

    private func addSamples(in app: XCUIApplication) {
        tapTab("导入", in: app)
        let addButton = element(app, "sampleAddButton")
        XCTAssertTrue(addButton.waitForExistence(timeout: 20))
        addButton.tap()
        _ = waitForLabel(
            app,
            identifier: "importCategorySummary",
            contains: "导入 3",
            timeout: 60
        )
    }

    private func openSettings(in app: XCUIApplication) {
        let settings = element(app, "librarySettingsButton")
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        XCTAssertTrue(
            element(app, "settingsCloseButton").waitForExistence(timeout: 20),
            "Settings sheet did not open"
        )
    }

    /// The inline navigation bar can be hidden while the Form is scrolled far
    /// down on this runtime. Scroll back first; if the sheet dismisses during
    /// that gesture, that already achieved the goal.
    private func dismissSettings(in app: XCUIApplication) {
        let close = element(app, "settingsCloseButton")
        var swipes = 0
        while !(close.exists && close.isHittable), swipes < 10 {
            if !element(app, "sampleCountText").exists {
                return
            }
            app.swipeDown()
            swipes += 1
        }
        if close.exists && close.isHittable {
            close.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        waitForDisappearance(element(app, "sampleCountText"), timeout: 10)
    }

    private func libraryRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "libraryItem-")
        )
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

    private func tapTab(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Missing tab \(label)")
        button.tap()
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
