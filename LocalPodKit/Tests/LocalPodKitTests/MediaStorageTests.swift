import Foundation
import XCTest
@testable import LocalPodKit

final class MediaStorageTests: XCTestCase {
    func testSessionAndRelativePathRoundTrip() throws {
        let root = try TemporaryDirectory()
        let storage = try MediaStorage(applicationSupportRoot: root.url)
        let session = try storage.newSessionURL()
        let file = session.appendingPathComponent("Season 1/Episode 001.m4a")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("test".utf8).write(to: file)

        let relative = try storage.relativePath(for: file)
        XCTAssertTrue(relative.hasPrefix("Media/Imports/"))
        XCTAssertEqual(try storage.url(forRelativePath: relative), file)
    }

    func testRejectsFileOutsideRoot() throws {
        let root = try TemporaryDirectory()
        let other = try TemporaryDirectory()
        let storage = try MediaStorage(applicationSupportRoot: root.url)
        let outside = try other.write("outside.m4a")

        XCTAssertThrowsError(try storage.relativePath(for: outside))
    }

    func testTraversalRelativePathStaysInsideRoot() throws {
        let root = try TemporaryDirectory()
        let storage = try MediaStorage(applicationSupportRoot: root.url)
        let resolved = try storage.url(forRelativePath: "../../etc/passwd")
        XCTAssertTrue(resolved.path.hasPrefix(root.url.path + "/"))
    }
}
