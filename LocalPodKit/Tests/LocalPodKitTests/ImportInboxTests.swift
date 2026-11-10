import Foundation
import XCTest
@testable import LocalPodKit

final class ImportInboxTests: XCTestCase {
    func testStagePendingAndRemove() throws {
        let documents = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        let inbox = try ImportInbox(documentsRoot: documents.url)
        let source = try outside.write("My Episode.m4a", bytes: 24)

        let staged = try inbox.stage(url: source)
        XCTAssertTrue(staged.path.hasPrefix(inbox.directoryURL.path + "/"))
        XCTAssertEqual(try inbox.pendingURLs().count, 1)

        try inbox.remove(staged)
        XCTAssertEqual(try inbox.pendingURLs().count, 0)
    }

    func testStageCollisionGetsUniqueName() throws {
        let documents = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        let inbox = try ImportInbox(documentsRoot: documents.url)
        let source = try outside.write("Episode.m4a", bytes: 24)

        let first = try inbox.stage(url: source)
        let second = try inbox.stage(url: source)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.lastPathComponent.contains("-2"))
    }
}
