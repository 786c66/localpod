import Foundation
import XCTest
@testable import LocalPodKit

final class TemporaryDirectory {
    let url: URL

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalPodKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        self.url = url
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func write(_ relativePath: String, bytes: Int = 16) throws -> URL {
        let data = Data(repeating: 0x41, count: bytes)
        return try write(relativePath, data: data)
    }

    @discardableResult
    func write(_ relativePath: String, data: Data) throws -> URL {
        let url = self.url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
        return url
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ImportProgress] = []

    func append(_ progress: ImportProgress) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(progress)
    }

    var all: [ImportProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var last: ImportProgress? {
        lock.lock()
        defer { lock.unlock() }
        return storage.last
    }
}

enum TestFixtures {
    static var audioURL: URL {
        guard let url = Bundle.module.url(forResource: "demo-audio", withExtension: "m4a") else {
            fatalError("Missing demo-audio.m4a test fixture")
        }
        return url
    }

    static var videoURL: URL {
        guard let url = Bundle.module.url(forResource: "demo-h264", withExtension: "mp4") else {
            fatalError("Missing demo-h264.mp4 test fixture")
        }
        return url
    }
}

struct FakeFolderScanner: FolderScanning {
    let result: ScanResult

    func scan(rootURL: URL, limits: FolderScanner.Limits) throws -> ScanResult {
        result
    }
}

struct FakeMediaProbe: MediaProbing {
    var duration: Double? = 12.5
    var artwork: Data?
    var error: Error?

    func probe(url: URL, kindHint: MediaKind) async throws -> ProbedMedia {
        if let error { throw error }
        return ProbedMedia(
            durationSeconds: duration,
            hasVideoTrack: kindHint.isVideo,
            hasAudioTrack: !kindHint.isVideo,
            title: nil,
            artworkJPEGData: artwork
        )
    }
}

struct FailingMediaProbe: MediaProbing {
    func probe(url: URL, kindHint: MediaKind) async throws -> ProbedMedia {
        throw MediaProbeError.notPlayable(url)
    }
}

final class FakeCloudDownloader: CloudDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var failuresRemaining: Int
    private(set) var callCount = 0

    init(failuresBeforeSuccess: Int = 0) {
        self.failuresRemaining = failuresBeforeSuccess
    }

    func ensureDownloaded(
        at url: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        let shouldFail = lock.withLock {
            callCount += 1
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                return true
            }
            return false
        }

        if shouldFail {
            throw CloudDownloadError.providerUnavailable(url, "offline")
        }
        progress(1)
    }
}
