import Foundation
import XCTest
@testable import LocalPodKit

final class MediaProbeTests: XCTestCase {
    func testAudioMetadata() async throws {
        let result = try await AVMediaProbe().probe(
            url: TestFixtures.audioURL,
            kindHint: .audio
        )
        XCTAssertEqual(result.durationSeconds ?? 0, 20, accuracy: 0.5)
        XCTAssertFalse(result.hasVideoTrack)
        XCTAssertTrue(result.hasAudioTrack)
    }

    func testVideoMetadataAndThumbnail() async throws {
        let result = try await AVMediaProbe().probe(
            url: TestFixtures.videoURL,
            kindHint: .video
        )
        XCTAssertGreaterThan(result.durationSeconds ?? 0, 0)
        XCTAssertTrue(result.hasVideoTrack)
        XCTAssertNotNil(result.artworkJPEGData)
        XCTAssertGreaterThan(result.artworkJPEGData?.count ?? 0, 100)
    }

    func testCorruptFileFailsProbe() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.write("broken.m4a", bytes: 128)
        do {
            _ = try await AVMediaProbe().probe(url: url, kindHint: .audio)
            XCTFail("Expected probe failure")
        } catch {
            XCTAssertTrue(error is MediaProbeError)
        }
    }

    func testLocalFileICloudDownloaderIsNoOp() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.write("local.m4a", bytes: 16)
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
        guard values.isUbiquitousItem != true else {
            throw XCTSkip("Test directory unexpectedly reports as iCloud")
        }
        try await ICloudDownloader().ensureDownloaded(at: url) { fraction in
            XCTAssertEqual(fraction, 1)
        }
    }
}
