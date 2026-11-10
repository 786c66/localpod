import Foundation
import XCTest
@testable import LocalPodKit

final class FolderScannerTests: XCTestCase {
    func testScansThreeLevelsAndSkipsUnsupported() throws {
        let directory = try TemporaryDirectory()
        var expectedBytes: Int64 = 0

        for index in 0..<100 {
            let season = index / 40 + 1
            let disc = (index % 40) / 10 + 1
            let name = String(format: "Episode %03d.m4a", index + 1)
            let size = 100 + index
            try directory.write("Season \(season)/Disc \(disc)/\(name)", bytes: size)
            expectedBytes += Int64(size)
        }
        try directory.write("notes.txt", bytes: 10)
        try directory.write(".hidden.m4a", bytes: 10)

        let result = try FolderScanner().scan(rootURL: directory.url)

        XCTAssertEqual(result.files.count, 100)
        XCTAssertEqual(result.skippedUnsupportedCount, 1)
        XCTAssertEqual(result.unsupportedFiles.first?.relativePath, "notes.txt")
        XCTAssertEqual(result.totalCandidates, 101)
        XCTAssertEqual(result.truncated, false)
        XCTAssertEqual(result.issues.count, 0)
        XCTAssertEqual(result.totalBytes, expectedBytes)
        XCTAssertEqual(result.files.first?.relativePath, "Season 1/Disc 1/Episode 001.m4a")
        XCTAssertEqual(result.files.last?.relativePath, "Season 3/Disc 2/Episode 100.m4a")
        XCTAssertTrue(result.files.allSatisfy { $0.kind == .audio })
    }

    func testSortsNaturally() throws {
        let directory = try TemporaryDirectory()
        try directory.write("Episode 10.m4a")
        try directory.write("Episode 2.m4a")
        try directory.write("Episode 1.m4a")

        let result = try FolderScanner().scan(rootURL: directory.url)
        XCTAssertEqual(
            result.files.map(\.relativePath),
            ["Episode 1.m4a", "Episode 2.m4a", "Episode 10.m4a"]
        )
    }

    func testFileLimitTruncates() throws {
        let directory = try TemporaryDirectory()
        for index in 0..<20 {
            try directory.write("file-\(index).m4a")
        }

        let result = try FolderScanner().scan(
            rootURL: directory.url,
            limits: .init(maxFiles: 5)
        )
        XCTAssertEqual(result.files.count, 5)
        XCTAssertTrue(result.truncated)
    }

    func testSingleFileScan() throws {
        let directory = try TemporaryDirectory()
        let url = try directory.write("single.mp4", bytes: 32)
        let file = try FolderScanner().scannedFile(for: url)
        XCTAssertEqual(file.kind, .video)
        XCTAssertEqual(file.byteSize, 32)
        XCTAssertEqual(file.relativePath, "single.mp4")
    }

    func testSupportedMediaTypes() {
        XCTAssertEqual(SupportedMedia.kind(for: URL(fileURLWithPath: "/tmp/a.m4a")), .audio)
        XCTAssertEqual(SupportedMedia.kind(for: URL(fileURLWithPath: "/tmp/a.mp3")), .audio)
        XCTAssertEqual(SupportedMedia.kind(for: URL(fileURLWithPath: "/tmp/a.mp4")), .video)
        XCTAssertEqual(SupportedMedia.kind(for: URL(fileURLWithPath: "/tmp/a.mov")), .video)
        XCTAssertNil(SupportedMedia.kind(for: URL(fileURLWithPath: "/tmp/a.txt")))
    }
}
