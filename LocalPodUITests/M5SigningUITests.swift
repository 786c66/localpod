import XCTest

@MainActor
final class M5SigningUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFakeExpiryBannerShowsDaysRemainingAndAdvice() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m5-skip-onboarding",
            "--m5-fake-signing-expiry-days",
            "5"
        ])
        tapTab("诊断", in: app)

        let banner = element(app, "signingExpiryBanner")
        XCTAssertTrue(
            banner.waitForExistence(timeout: 20),
            "The signing banner must appear when a profile expiry exists"
        )
        waitForLabel(banner, contains: "签名将在 5 天后到期")
        XCTAssertTrue(
            banner.label.contains("同一 Bundle ID 重签"),
            "unexpected banner label \(banner.label)"
        )
        XCTAssertTrue(
            banner.label.contains("重签不会清除资料库"),
            "unexpected banner label \(banner.label)"
        )
        attach(app, name: "M5-signing-expiry-banner")
    }

    func testSigningReminderTogglePersistsAfterDisablingAndRelaunch() throws {
        let app = makeApp(["--m0-reset-data", "--m5-skip-onboarding"])
        openSettings(in: app)

        let toggle = element(app, "settingsSigningReminderToggle")
        reveal(toggle, in: app)
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "Missing settingsSigningReminderToggle"
        )
        XCTAssertEqual(
            toggle.value as? String,
            "1",
            "Signing reminder should default to enabled"
        )
        attach(app, name: "M5-signing-toggle-enabled")

        // The Form row's center is the label; on this runtime only the switch
        // control itself activates, so target its trailing side explicitly.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitForToggle(toggle, isOn: false)
        attach(app, name: "M5-signing-toggle-disabled")

        app.terminate()

        // No --m0-reset-data: the UserDefaults value must survive relaunch.
        let relaunched = makeApp(["--m5-skip-onboarding"])
        openSettings(in: relaunched)
        let restoredToggle = element(relaunched, "settingsSigningReminderToggle")
        reveal(restoredToggle, in: relaunched)
        XCTAssertTrue(restoredToggle.waitForExistence(timeout: 10))
        XCTAssertEqual(
            restoredToggle.value as? String,
            "0",
            "Signing reminder must stay disabled after relaunch"
        )
        attach(relaunched, name: "M5-signing-toggle-persisted-off")
    }

    // MARK: - Helpers

    private func makeApp(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchPinned()
        return app
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

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForLabel(
        _ element: XCUIElement,
        contains text: String,
        timeout: TimeInterval = 15
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Element label did not contain \(text): \(element.label)"
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

    private func tapTab(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Missing tab \(label)")
        button.tap()
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
