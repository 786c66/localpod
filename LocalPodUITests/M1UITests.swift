import XCTest

@MainActor
final class M1UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeApp(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
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

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 {
            if element.exists { return }
            app.swipeUp()
        }
    }

    func testAcceptanceImportReportDedupAndLibrary() throws {
        let app = makeApp(["--m0-reset-data", "--m1-auto-acceptance-import"])

        waitForLabel(app, identifier: "importCategorySummary", contains: "导入 97", timeout: 120)
        let category = app.descendants(matching: .any)["importCategorySummary"]
        XCTAssertTrue(category.label.contains("重复 1"))
        XCTAssertTrue(category.label.contains("不支持 2"))
        attach(app, name: "M1-import-report")

        let importAgain = app.descendants(matching: .any)["importAcceptanceFolderButton"]
        XCTAssertTrue(importAgain.waitForExistence(timeout: 10))
        importAgain.tap()
        waitForLabel(app, identifier: "importCategorySummary", contains: "导入 0", timeout: 120)
        let secondCategory = app.descendants(matching: .any)["importCategorySummary"]
        XCTAssertTrue(secondCategory.label.contains("重复 98"))
        XCTAssertTrue(secondCategory.label.contains("不支持 2"))

        app.buttons["资料库"].tap()
        let stats = waitForLabel(app, identifier: "libraryStatsText", contains: "97 条", timeout: 20)
        XCTAssertTrue(stats.label.contains("1 个合集"), "Repeated import must not create another collection")
        attach(app, name: "M1-library")

        let row = app.descendants(matching: .any)["libraryItem-Episode 097"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Library list did not render")
        row.tap()
        let deleteButton = app.descendants(matching: .any)["detailDeleteButton"]
        XCTAssertTrue(app.navigationBars["Episode 097"].waitForExistence(timeout: 10))
        let duration = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "0:20")
        ).firstMatch
        XCTAssertTrue(duration.waitForExistence(timeout: 10))
        reveal(deleteButton, in: app)
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 10))
        attach(app, name: "M1-item-detail")
    }

    func testCancelDuringSlowImport() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m1-auto-acceptance-import",
            "--m1-slow-copy"
        ])

        let progress = app.descendants(matching: .any)["importProgressText"]
        XCTAssertTrue(progress.waitForExistence(timeout: 30))
        let cancel = app.descendants(matching: .any)["cancelImportButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["importCancelledText"].waitForExistence(timeout: 30)
        )
        attach(app, name: "M1-import-cancelled")

        app.buttons["资料库"].tap()
        let stats = app.descendants(matching: .any)["libraryStatsText"]
        XCTAssertTrue(stats.waitForExistence(timeout: 20))
        XCTAssertFalse(stats.label.contains("97 条"), "Cancelled import should not import all files")
    }

    func testForceKillLeavesNoDirtyLibraryAndMaintenanceCleansStaging() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m1-auto-acceptance-import",
            "--m1-slow-copy"
        ])
        let progress = app.descendants(matching: .any)["importProgressText"]
        XCTAssertTrue(progress.waitForExistence(timeout: 30))
        let copyingExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES %@", "文件 [1-9][0-9]*/100.*"),
            object: progress
        )
        wait(for: [copyingExpectation], timeout: 30)
        app.terminate()

        let relaunched = makeApp(["--m1-auto-maintenance"])
        let detail = relaunched.descendants(matching: .any)["maintenanceDetailText"]
        XCTAssertTrue(detail.waitForExistence(timeout: 30))
        XCTAssertFalse(detail.label.contains("staging 0"), "Expected a stale staging session to be cleaned")
        attach(relaunched, name: "M1-maintenance-after-kill")

        relaunched.buttons["资料库"].tap()
        let stats = relaunched.descendants(matching: .any)["libraryStatsText"]
        XCTAssertTrue(stats.waitForExistence(timeout: 20))
        XCTAssertTrue(stats.label.contains("0 条"))
    }

    func testDeleteItemUpdatesLibraryAndStorage() throws {
        let app = makeApp(["--m0-reset-data", "--m1-auto-acceptance-import"])
        waitForLabel(app, identifier: "importCategorySummary", contains: "导入 97", timeout: 120)

        app.buttons["资料库"].tap()
        waitForLabel(app, identifier: "libraryStatsText", contains: "97 条", timeout: 20)

        let row = app.descendants(matching: .any)["libraryItem-Episode 097"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Library list did not render")
        row.tap()

        let deleteButton = app.descendants(matching: .any)["detailDeleteButton"]
        reveal(deleteButton, in: app)
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 10))
        deleteButton.tap()

        let alertDelete = app.alerts.buttons["删除"]
        XCTAssertTrue(alertDelete.waitForExistence(timeout: 10))
        alertDelete.tap()

        waitForLabel(app, identifier: "libraryStatsText", contains: "96 条", timeout: 20)
        attach(app, name: "M1-after-delete")
    }

    func testLibraryFiveThousandItemsScroll() throws {
        let app = makeApp(["--m0-reset-data", "--m1-seed-library-5000"])
        waitForLabel(app, identifier: "libraryStatsText", contains: "5,000 条", timeout: 60)
        attach(app, name: "M1-library-5000")
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
    }
}
