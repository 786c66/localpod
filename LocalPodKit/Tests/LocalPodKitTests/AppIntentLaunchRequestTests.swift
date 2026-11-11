import Foundation
import XCTest
@testable import LocalPodKit

final class AppIntentLaunchRequestTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppIntentLaunchRequestTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Raw value codec

    func testRawValueRoundTrip() {
        let requests: [AppIntentLaunchRequest] = [
            .continuePlayback,
            .openCollection(name: "智能合集 B"),
            .openCollection(name: "合集:含:冒号"),
            .openCollection(name: "含 空格 的合集")
        ]
        for request in requests {
            XCTAssertEqual(
                AppIntentLaunchRequest(rawValue: request.rawValue),
                request,
                "round trip failed for \(request.rawValue)"
            )
        }
        XCTAssertEqual(AppIntentLaunchRequest.continuePlayback.rawValue, "continue-playback")
        XCTAssertEqual(
            AppIntentLaunchRequest.openCollection(name: "a:b").rawValue,
            "open-collection:a:b",
            "only the first colon separates the code from the name"
        )
    }

    func testInvalidRawValuesAreRejected() {
        for rawValue in [
            "",
            "play",
            "continue-playback:extra",
            "CONTINUE-PLAYBACK",
            "open-collection",
            "open-collection:"
        ] {
            XCTAssertNil(
                AppIntentLaunchRequest(rawValue: rawValue),
                "unexpectedly parsed \(rawValue)"
            )
        }
    }

    // MARK: - URL parsing

    func testParsesContinuePlaybackURL() {
        XCTAssertEqual(
            AppIntentLaunchRequest(url: URL(string: "localpod://play")!),
            .continuePlayback
        )
    }

    func testParsesOpenCollectionURLWithPercentEncoding() {
        var components = URLComponents()
        components.scheme = "localpod"
        components.host = "collection"
        components.queryItems = [URLQueryItem(name: "name", value: "智能合集 B: 含冒号")]
        XCTAssertEqual(
            AppIntentLaunchRequest(url: components.url!),
            .openCollection(name: "智能合集 B: 含冒号")
        )
    }

    func testRejectsInvalidURLs() {
        let invalidURLs = [
            "localpod://collection",
            "localpod://collection?name=",
            "localpod://collection?other=value",
            "localpod://unknown",
            "https://play",
            "localpod:///play"
        ]
        for rawURL in invalidURLs {
            XCTAssertNil(
                AppIntentLaunchRequest(url: URL(string: rawURL)!),
                "unexpectedly parsed \(rawURL)"
            )
        }
    }

    // MARK: - Store

    func testStoreRoundTripAndConsumeOnce() {
        XCTAssertNil(AppIntentLaunchRequestStore.peek(defaults: defaults))

        AppIntentLaunchRequestStore.save(.openCollection(name: "智能合集 B"), defaults: defaults)
        XCTAssertEqual(
            AppIntentLaunchRequestStore.peek(defaults: defaults),
            .openCollection(name: "智能合集 B")
        )
        XCTAssertEqual(
            AppIntentLaunchRequestStore.consume(defaults: defaults),
            .openCollection(name: "智能合集 B")
        )
        XCTAssertNil(
            AppIntentLaunchRequestStore.consume(defaults: defaults),
            "second consume must return nil"
        )
        XCTAssertNil(AppIntentLaunchRequestStore.peek(defaults: defaults))
    }

    func testPeekDoesNotConsumeAndClearRemovesRequest() {
        AppIntentLaunchRequestStore.save(.continuePlayback, defaults: defaults)
        XCTAssertEqual(AppIntentLaunchRequestStore.peek(defaults: defaults), .continuePlayback)
        XCTAssertEqual(
            AppIntentLaunchRequestStore.peek(defaults: defaults),
            .continuePlayback,
            "peek must not consume"
        )
        XCTAssertEqual(AppIntentLaunchRequestStore.consume(defaults: defaults), .continuePlayback)

        AppIntentLaunchRequestStore.save(.continuePlayback, defaults: defaults)
        AppIntentLaunchRequestStore.clear(defaults: defaults)
        XCTAssertNil(AppIntentLaunchRequestStore.peek(defaults: defaults))
    }
}
