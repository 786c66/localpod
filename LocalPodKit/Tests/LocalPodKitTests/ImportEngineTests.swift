import Foundation
import XCTest
@testable import LocalPodKit

final class ImportEngineTests: XCTestCase {
    func testImportsAllFilesAndReportsFinishedProgress() async throws {
        let source = try TemporaryDirectory()
        let destination = try TemporaryDirectory()

        try source.write("Season 1/Disc 1/Episode 001.m4a", bytes: 128)
        try source.write("Season 1/Disc 1/Episode 002.m4a", bytes: 256)
        try source.write("Season 2/Episode 003.mp4", bytes: 512)

        let recorder = ProgressRecorder()
        let result = try await ImportEngine().scanAndImport(
            rootURL: source.url,
            destinationRootURL: destination.url,
            progress: { recorder.append($0) }
        )

        XCTAssertEqual(result.importedFiles.count, 3)
        XCTAssertEqual(result.issues.count, 0)
        XCTAssertEqual(result.cancelled, false)
        XCTAssertEqual(result.copiedBytes, 896)
        XCTAssertEqual(result.totalBytes, 896)
        XCTAssertEqual(recorder.last?.phase, .finished)
        XCTAssertEqual(recorder.last?.copiedBytes, 896)
        XCTAssertEqual(recorder.last?.completedFiles, 3)

        let first = destination.url.appendingPathComponent("Season 1/Disc 1/Episode 001.m4a")
        let third = destination.url.appendingPathComponent("Season 2/Episode 003.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: third.path))
    }

    func testCollisionGetsUniqueName() async throws {
        let source = try TemporaryDirectory()
        let destination = try TemporaryDirectory()
        try source.write("same.m4a", bytes: 32)

        let engine = ImportEngine()
        let first = try await engine.scanAndImport(
            rootURL: source.url,
            destinationRootURL: destination.url
        )
        let second = try await engine.scanAndImport(
            rootURL: source.url,
            destinationRootURL: destination.url
        )

        XCTAssertEqual(first.importedFiles.count, 1)
        XCTAssertEqual(second.importedFiles.count, 1)
        XCTAssertNotEqual(
            first.importedFiles[0].destinationURL,
            second.importedFiles[0].destinationURL
        )
        XCTAssertTrue(second.importedFiles[0].destinationURL.lastPathComponent.contains("-2"))
    }

    func testSingleFileRootCanBeImported() async throws {
        let source = try TemporaryDirectory()
        let destination = try TemporaryDirectory()
        let file = try source.write("single.m4a", bytes: 64)

        let result = try await ImportEngine().scanAndImport(
            rootURL: file,
            destinationRootURL: destination.url
        )
        XCTAssertEqual(result.importedFiles.count, 1)
        XCTAssertEqual(result.totalBytes, 64)
    }

    func testPathSanitizerRejectsTraversal() {
        XCTAssertEqual(PathSanitizer.sanitizeRelativePath("../evil.m4a"), "_/evil.m4a")
        XCTAssertEqual(PathSanitizer.sanitizeRelativePath("a//b/c.m4a"), "a/b/c.m4a")
        XCTAssertEqual(PathSanitizer.sanitizeRelativePath(""), "untitled")
    }
}
