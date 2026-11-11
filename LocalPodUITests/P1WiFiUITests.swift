import XCTest

@MainActor
final class P1WiFiUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--m0-reset-data", "--p1-wifi-demo"]
        app.launchPinned()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 10
    ) {
        // Scroll down one swipe at a time. A fixed multi-swipe run can
        // overshoot past the row (unloading it from the lazy List), and a
        // downward reset can dismiss the settings sheet, so every swipe is
        // followed by a hittability check and the direction only reverses
        // after the first pass ends.
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

    func testWiFiUploadScreenStartsShowsPINURLAndStops() throws {
        let app = makeApp()
        let settingsButton = element(app, "librarySettingsButton")
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 20))
        settingsButton.tap()

        let link = element(app, "wifiUploadLink")
        reveal(link, in: app)
        link.tap()

        XCTAssertTrue(
            app.navigationBars["Wi-Fi 上传"].waitForExistence(timeout: 10),
            "Wi-Fi upload screen did not open"
        )
        let start = element(app, "wifiStartButton")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        let status = element(app, "wifiStatusText")
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "正在监听局域网")

        let pin = element(app, "wifiPINText")
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertTrue(pin.label.contains("246810"), "unexpected PIN label \(pin.label)")

        let url = element(app, "wifiURLText")
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        XCTAssertEqual(url.label, "http://192.0.2.10:8080")

        let qr = element(app, "wifiQRCode")
        reveal(qr, in: app)
        XCTAssertTrue(qr.exists)
        let received = element(app, "wifiReceivedCount")
        reveal(received, in: app)
        XCTAssertTrue(received.exists)
        attachScreenshot(app, name: "P1-wifi-running")

        let stop = element(app, "wifiStopButton")
        reveal(stop, in: app)
        stop.tap()
        XCTAssertTrue(
            element(app, "wifiStartButton").waitForExistence(timeout: 10),
            "Stopping should return to the idle screen"
        )
        attachScreenshot(app, name: "P1-wifi-stopped")
    }

    func testCompletedUploadIsImportedOnLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--m0-reset-data", "--p1-wifi-staged-upload"]
        app.launchPinned()

        let tab = app.buttons["资料库"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()

        let row = element(app, "libraryItem-Wi-Fi 示例")
        XCTAssertTrue(
            row.waitForExistence(timeout: 30),
            "Completed Wi-Fi session was not recovered and imported on launch"
        )
        attachScreenshot(app, name: "P1-wifi-recovered-import")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
