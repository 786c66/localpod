import XCTest

/// P2 备份/恢复 (backup/restore) UI test. Seams:
/// - Launch 1: `--m0-reset-data --m3-seed-playable-library --p2-export-backup`
///   seeds the three-item M3 library, then snapshots it to
///   Documents/p2-backup.json at bootstrap.
/// - Launch 2: `--m0-reset-data --p2-import-backup` wipes the store and
///   restores that file during bootstrap, then `--m3-open-settings` shows the
///   new section so the restore summary is directly verifiable.
///
/// The Settings section itself is exercised through its identifiers
/// (backupExportSummary / backupRestoreSummary) without driving the document
/// picker, which cannot be automated reliably in-sandbox.
@MainActor
final class P2BackupUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 14
    ) {
        // Swipe one at a time with a hittability check, reversing direction
        // after the first pass (same helper as the P1/P2 suites).
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

    private func tapLibraryTab(_ app: XCUIApplication) {
        let button = app.buttons["资料库"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Missing 资料库 tab")
        button.tap()
    }

    private func waitForLibrary(_ app: XCUIApplication) {
        tapLibraryTab(app)
        let stats = element(app, "libraryStatsText")
        reveal(stats, in: app)
        XCTAssertTrue(stats.waitForExistence(timeout: 20))
    }

    private func openSettings(_ app: XCUIApplication) {
        let settingsButton = element(app, "librarySettingsButton")
        reveal(settingsButton, in: app)
        settingsButton.tap()
        XCTAssertTrue(
            element(app, "settingsCloseButton").waitForExistence(timeout: 20),
            "Settings sheet must open"
        )
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testExportThenRestoreRoundTrip() throws {
        // Launch 1: seed the M3 library and export its backup at bootstrap.
        let first = XCUIApplication()
        first.launchArguments = [
            "--m0-reset-data",
            "--m3-seed-playable-library",
            "--p2-export-backup"
        ]
        first.launchPinned()
        waitForLibrary(first)

        // Three seeded items exist before the export.
        let rowA = element(first, "libraryItem-队列测试 A")
        reveal(rowA, in: first)
        XCTAssertTrue(rowA.waitForExistence(timeout: 20))

        // Open Settings and export through the real UI so the section, the
        // share sheet, and the summary line are all exercised. The sheet
        // covers the form, so it must be dismissed before the summary can be
        // revealed again.
        openSettings(first)
        let exportButton = element(first, "backupExportButton")
        reveal(exportButton, in: first)
        exportButton.tap()

        let shareLink = element(first, "backupShareLink")
        XCTAssertTrue(
            shareLink.waitForExistence(timeout: 10),
            "Share sheet must present the exported backup"
        )
        let shareDone = element(first, "backupShareDone")
        XCTAssertTrue(
            shareDone.waitForExistence(timeout: 10),
            "Share sheet must expose its close button"
        )
        shareDone.tap()
        XCTAssertTrue(
            shareLink.waitForNonExistence(timeout: 10),
            "Share sheet must dismiss after tapping 完成"
        )

        let exportSummary = element(first, "backupExportSummary")
        reveal(exportSummary, in: first)
        // 3 seeded items, no playlists, 2 progress rows seeded by M3.
        XCTAssertTrue(
            exportSummary.waitForExistence(timeout: 10),
            "Export summary must appear after exporting"
        )
        XCTAssertTrue(
            exportSummary.label.contains("3 条目"),
            "Export summary must count the seeded items: \(exportSummary.label)"
        )
        attachScreenshot(first, name: "P2-backup-exported")
        first.terminate()

        // Launch 2: wipe the store, then restore the exported backup at
        // bootstrap. The restore reconnects the SAME item ids, so the library
        // shows the seeded rows again (their media files were also reset and
        // are re-staged by the M3 seed only on launch 1; here the restored
        // rows must come back marked missing, which the relink flow handles).
        let second = XCUIApplication()
        second.launchArguments = [
            "--m0-reset-data",
            "--p2-import-backup",
            "--m3-open-settings"
        ]
        second.launchPinned()

        let restoreSummary = element(second, "backupRestoreSummary")
        // Settings opens directly (--m3-open-settings); the restore already
        // happened during bootstrap, so the summary line is present. Reveal
        // BEFORE waiting: Form rows below the fold do not exist in the
        // accessibility tree until scrolled into view, so a bare
        // waitForExistence would time out on an unscrolled form.
        reveal(restoreSummary, in: second)
        XCTAssertTrue(
            restoreSummary.waitForExistence(timeout: 10),
            "Restore summary must be visible in Settings"
        )
        XCTAssertTrue(
            restoreSummary.label.contains("已恢复 3 条目"),
            "Restore summary must report the three restored items: \(restoreSummary.label)"
        )
        attachScreenshot(second, name: "P2-backup-restored-settings")

        // The library shows the restored items (same ids as launch 1).
        // The summary assertion scrolled the form down, so the close button
        // (top of the sheet) is offscreen; reveal it — a bare exists/hittable
        // guard silently skips the tap and leaves the sheet covering the
        // screen, which makes every later library query fail.
        let closeButton = element(second, "settingsCloseButton")
        reveal(closeButton, in: second)
        closeButton.tap()
        waitForLibrary(second)
        let restoredRow = element(second, "libraryItem-队列测试 A")
        reveal(restoredRow, in: second)
        XCTAssertTrue(
            restoredRow.waitForExistence(timeout: 20),
            "Restored item A must appear in the library after the reset+import"
        )
        attachScreenshot(second, name: "P2-backup-restored-library")
    }
}
