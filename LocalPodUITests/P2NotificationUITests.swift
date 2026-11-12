import XCTest

/// P2 通知 (local import notifications) UI test.
///
/// The system authorization dialog is a springboard alert and the simulator
/// has no real notification delivery, so the suite exercises the real pipeline
/// through DEBUG seams instead:
/// - `--m0-seed-inbox` + `--m0-auto-inbox` run one file through the standard
///   inbox import path.
/// - `--p2-enable-import-notifications` persists the setting without asking
///   for permission.
/// - `--p2-force-inactive-for-notifications` makes the coordinator take the
///   "app is backgrounded" branch so the decision is not suppressed.
/// - `--p2-print-import-notification` publishes the decision to UserDefaults,
///   which Settings surfaces as `lastImportNotificationText`.
@MainActor
final class P2NotificationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testImportNotificationDecisionAndTogglePersistence() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--m0-reset-data",
            "--m0-seed-inbox",
            "--m0-auto-inbox",
            "--p2-enable-import-notifications",
            "--p2-force-inactive-for-notifications",
            "--p2-print-import-notification"
        ]
        app.launchPinned()

        // The seeded inbox file is imported by the real pipeline. Wait for the
        // Inbox result before opening Settings so the decision is already
        // published when the section first renders.
        let inboxSummary = element(app, "inboxCategorySummary")
        XCTAssertTrue(
            inboxSummary.waitForExistence(timeout: 45),
            "The seeded inbox import must finish"
        )
        XCTAssertTrue(
            inboxSummary.label.contains("导入 1"),
            "Expected one imported inbox file: \(inboxSummary.label)"
        )

        // Inbox is a Settings subpage now: the auto-inbox launch link opens
        // that sheet directly. Close it before switching tabs — the tab bar
        // sits behind the sheet and is not hittable while it is up.
        closeSettings(in: app)
        tapTab("资料库", in: app)
        openSettings(in: app)

        let toggle = element(app, "importNotificationsToggle")
        reveal(toggle, in: app)
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "Missing importNotificationsToggle"
        )
        XCTAssertEqual(
            toggle.value as? String,
            "1",
            "The DEBUG setting seam must start with notifications enabled"
        )
        attach(app, name: "P2-notification-toggle-enabled")

        // The force-inactive seam proves the real coordinator → policy →
        // notifier wiring produced the success decision for a backgrounded
        // app. No system permission was requested, so delivery itself is a
        // silent no-op; the decision text is the observable seam.
        let lastDecision = element(app, "lastImportNotificationText")
        reveal(lastDecision, in: app)
        XCTAssertTrue(
            lastDecision.waitForExistence(timeout: 10),
            "Settings must surface the last import notification decision"
        )
        XCTAssertTrue(
            lastDecision.label.contains("导入完成"),
            "Expected a success notification decision: \(lastDecision.label)"
        )
        XCTAssertTrue(
            lastDecision.label.contains("1 个条目"),
            "Expected the notification to count the imported file: \(lastDecision.label)"
        )
        attach(app, name: "P2-notification-decision")

        // Disabling never requests authorization, so this is dialog-free.
        reveal(toggle, in: app)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitForToggle(toggle, isOn: false)
        attach(app, name: "P2-notification-toggle-disabled")
        app.terminate()

        // No --m0-reset-data: the UserDefaults value must survive relaunch.
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--m5-skip-onboarding"]
        relaunched.launchPinned()
        openSettings(in: relaunched)
        let restoredToggle = element(relaunched, "importNotificationsToggle")
        reveal(restoredToggle, in: relaunched)
        XCTAssertTrue(restoredToggle.waitForExistence(timeout: 10))
        XCTAssertEqual(
            restoredToggle.value as? String,
            "0",
            "Import notifications must stay disabled after relaunch"
        )
        attach(relaunched, name: "P2-notification-toggle-persisted-off")
    }

    // MARK: - Helpers

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func tapTab(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Missing tab \(label)")
        button.tap()
    }

    private func closeSettings(in app: XCUIApplication) {
        let close = element(app, "settingsCloseButton")
        XCTAssertTrue(close.waitForExistence(timeout: 20), "Missing settings close")
        close.tap()
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: close
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [gone], timeout: 10),
            .completed,
            "Settings sheet did not dismiss"
        )
    }

    private func openSettings(in app: XCUIApplication) {
        let settings = element(app, "librarySettingsButton")
        reveal(settings, in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        XCTAssertTrue(
            element(app, "settingsCloseButton").waitForExistence(timeout: 20),
            "Settings sheet did not open"
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

    private func waitForToggle(
        _ toggle: XCUIElement,
        isOn: Bool,
        timeout: TimeInterval = 10
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", isOn ? "1" : "0"),
            object: toggle
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Toggle did not become \(isOn ? "on" : "off"): \(String(describing: toggle.value))"
        )
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
