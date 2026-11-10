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
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: inbox.directoryURL.path), [staged.lastPathComponent])

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
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: inbox.directoryURL.path)
                .contains { $0.hasPrefix(".localpod-stage-") }
        )
    }

    func testStageFolderCopiesTreeWithoutTemporaryLeftovers() throws {
        let documents = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        let inbox = try ImportInbox(documentsRoot: documents.url)
        let source = outside.url.appendingPathComponent("Season", isDirectory: true)
        try outside.write("Season/Disc 1/Episode 1.m4a", bytes: 24)
        try outside.write("Season/Disc 1/Episode 2.m4a", bytes: 32)

        let staged = try inbox.stage(url: source)

        XCTAssertEqual(staged.lastPathComponent, "Season")
        let copied = try FileManager.default.contentsOfDirectory(atPath: staged.path).sorted()
        XCTAssertEqual(copied, ["Disc 1"])
        let nested = try FileManager.default.contentsOfDirectory(
            atPath: staged.appendingPathComponent("Disc 1").path
        ).sorted()
        XCTAssertEqual(nested, ["Episode 1.m4a", "Episode 2.m4a"])
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: inbox.directoryURL.path),
            ["Season"]
        )
    }

    func testCleanupStaleStagingRemovesOnlyOldTemporaries() throws {
        let documents = try TemporaryDirectory()
        let inbox = try ImportInbox(documentsRoot: documents.url)
        try inbox.ensureExists()
        let old = try documents.write("Import/.localpod-stage-old", bytes: 8)
        let recent = try documents.write("Import/.localpod-stage-recent", bytes: 8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-7200)],
            ofItemAtPath: old.path
        )

        XCTAssertEqual(try inbox.cleanupStaleStaging(olderThan: 3600), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
    }

    func testStageFailureLeavesNoPartialDestinationOrTemporaryItem() throws {
        let documents = try TemporaryDirectory()
        let inbox = try ImportInbox(documentsRoot: documents.url)
        let missing = documents.url.appendingPathComponent("Missing/Episode.m4a")

        XCTAssertThrowsError(try inbox.stage(url: missing))

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: inbox.directoryURL.path), [])
        XCTAssertEqual(try inbox.pendingURLs().count, 0)
    }
}
