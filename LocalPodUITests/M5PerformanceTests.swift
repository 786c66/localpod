import XCTest

/// M5 performance baselines. These tests intentionally do not assert
/// device-specific thresholds: they record and print simulator numbers only.
/// Real-device numbers must be gathered separately (see docs/M5-PERFORMANCE.md).
@MainActor
final class M5PerformanceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchPerformance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--m0-reset-data", "--m5-skip-onboarding"]

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launchPinned()
            app.terminate()
        }
    }

    func testLibraryScrollPerformanceWithFiveThousandItems() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--m0-reset-data",
            "--m5-skip-onboarding",
            "--m1-seed-library-5000"
        ]
        app.launchPinned()

        let stats = app.descendants(matching: .any)["libraryStatsText"]
        XCTAssertTrue(
            stats.waitForExistence(timeout: 90),
            "Seeded 5,000-item library did not finish loading"
        )
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "5,000 条"),
            object: stats
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 60),
            .completed,
            "Unexpected library size: \(stats.label)"
        )

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            // App-level swipes land on the visible library List. M1's 5,000-row
            // smoke test uses the same gesture, which is more reliable than
            // resolving the backing collection view on this runtime.
            app.swipeUp(velocity: .fast)
        }
    }
}
