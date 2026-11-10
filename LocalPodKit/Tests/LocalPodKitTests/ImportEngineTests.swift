import CryptoKit
import Foundation
import XCTest
@testable import LocalPodKit

final class ImportEngineTests: XCTestCase {
    private struct Roots {
        let storage: MediaStorage
        let media: URL
        let staging: URL
        let artwork: URL
    }

    private static func makeRoots() throws -> Roots {
        let root = try TemporaryDirectory()
        let storage = try MediaStorage(
            applicationSupportRoot: root.url.appendingPathComponent("Support"),
            cachesRoot: root.url.appendingPathComponent("Caches")
        )
        return Roots(
            storage: storage,
            media: try storage.mediaRootURL(),
            staging: try storage.stagingRootURL(),
            artwork: try storage.artworkRootURL()
        )
    }

    private static func importFolder(
        source: URL,
        roots: Roots,
        existing: Set<String> = [],
        relink: Set<String> = [],
        probe: any MediaProbing = FakeMediaProbe(),
        cloudDownloader: any CloudDownloading = FakeCloudDownloader(),
        scanner: (any FolderScanning)? = nil,
        retryCount: Int = 1,
        chunkDelay: Duration? = nil,
        progress: @escaping @Sendable (ImportProgress) -> Void = { _ in }
    ) async throws -> ImportRunResult {
        try await ImportEngine(scanner: scanner ?? FolderScanner()).importFolder(
            rootURL: source,
            source: .files,
            rootName: source.lastPathComponent,
            stagingRootURL: roots.staging,
            mediaRootURL: roots.media,
            artworkRootURL: roots.artwork,
            existingFingerprints: existing,
            relinkFingerprints: relink,
            options: ImportEngine.Options(
                chunkSize: 64 * 1024,
                chunkDelay: chunkDelay,
                cloudRetryCount: retryCount
            ),
            probe: probe,
            cloudDownloader: cloudDownloader,
            progress: progress
        )
    }

    func testImportsAllFilesAndReportsProgress() async throws {
        let source = try TemporaryDirectory()
        let roots = try Self.makeRoots()
        try source.write("Season 1/Disc 1/Episode 001.m4a", bytes: 128)
        try source.write("Season 1/Disc 1/Episode 002.m4a", bytes: 256)
        try source.write("Season 2/Episode 003.mp4", bytes: 512)

        let recorder = ProgressRecorder()
        let result = try await Self.importFolder(
            source: source.url,
            roots: roots,
            progress: { recorder.append($0) }
        )

        XCTAssertEqual(result.importedCount, 3)
        XCTAssertEqual(result.duplicateCount, 0)
        XCTAssertEqual(result.unsupportedCount, 0)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(result.cancelled, false)
        XCTAssertEqual(result.totalCandidates, 3)
        XCTAssertEqual(result.totalBytes, 896)
        XCTAssertEqual(result.copiedBytes, 896)
        XCTAssertEqual(recorder.last?.phase, .finished)
        XCTAssertEqual(recorder.last?.completedFiles, 3)
        XCTAssertEqual(recorder.last?.fractionCompleted, 1)
        XCTAssertEqual(result.importedFiles.first?.relativeFolderPath, "Season 1/Disc 1")
        XCTAssertEqual(result.importedFiles.first?.title, "Episode 001")
        XCTAssertEqual(result.importedFiles.first?.durationSeconds, 12.5)
        XCTAssertEqual(result.importedFiles.first?.fingerprint.count, 64)

        for file in result.importedFiles {
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.destinationURL.path))
        }
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: roots.media.path)
                .filter { !$0.hasPrefix(".") }.count,
            3
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: roots.staging.path).count,
            0
        )
    }

    func testDuplicateIsSkippedAndCounted() async throws {
        let source = try TemporaryDirectory()
        let roots = try Self.makeRoots()
        try source.write("one.m4a", data: Data(repeating: 0x42, count: 128))
        try source.write("two.m4a", data: Data(repeating: 0x42, count: 128))

        let result = try await Self.importFolder(source: source.url, roots: roots)

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.duplicateCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(result.totalCandidates, 2)
        XCTAssertEqual(result.importedFiles.count, 1)
        XCTAssertTrue(result.duplicateIssues[0].message.contains("内容重复"))
    }

    func testUnsupportedFilesAreReportedAndProgressCountsAllCandidates() async throws {
        let source = try TemporaryDirectory()
        let roots = try Self.makeRoots()
        try source.write("a.m4a", bytes: 32)
        try source.write("b.m4a", bytes: 33)
        try source.write("c.mp4", bytes: 34)
        try source.write("notes.txt", bytes: 8)
        try source.write("cover.jpg", bytes: 9)

        let recorder = ProgressRecorder()
        let result = try await Self.importFolder(
            source: source.url,
            roots: roots,
            progress: { recorder.append($0) }
        )

        XCTAssertEqual(result.importedCount, 3)
        XCTAssertEqual(result.unsupportedCount, 2)
        XCTAssertEqual(result.totalCandidates, 5)
        XCTAssertEqual(recorder.last?.completedFiles, 5)
        XCTAssertEqual(result.unsupportedIssues.map(\.relativePath).sorted(), ["cover.jpg", "notes.txt"])
        XCTAssertEqual(recorder.last?.phase, .finished)
    }

    func testCancellationKeepsCompletedFilesAndCleansStaging() async throws {
        let source = try TemporaryDirectory()
        let roots = try Self.makeRoots()
        try source.write("one.m4a", bytes: 2 * 1024 * 1024)
        try source.write("two.m4a", bytes: 2 * 1024 * 1024)

        let trigger = CancellationTrigger(cancelAfterCompletedFiles: 1)
        let task = Task {
            try await Self.importFolder(
                source: source.url,
                roots: roots,
                chunkDelay: .milliseconds(2),
                progress: { trigger.record($0) }
            )
        }
        trigger.setCancelAction { task.cancel() }
        let result = try await task.value

        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.failureIssues.count, 0)
        XCTAssertEqual(result.importedFiles.count, 1)
        XCTAssertTrue(result.importedFiles.allSatisfy {
            FileManager.default.fileExists(atPath: $0.destinationURL.path)
        })
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: roots.staging.path).count, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: roots.media.path).count, 1)
        XCTAssertEqual(result.importedCount + result.duplicateCount + result.failedCount + result.unsupportedCount, 1)
    }

    func testProbeFailureIsReportedAndLeavesNoFile() async throws {
        let source = try TemporaryDirectory()
        let roots = try Self.makeRoots()
        try source.write("broken.m4a", bytes: 64)

        let result = try await Self.importFolder(
            source: source.url,
            roots: roots,
            probe: FailingMediaProbe()
        )

        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(result.failureIssues.first?.kind, .probeFailed)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: roots.media.path).count, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: roots.staging.path).count, 0)
    }

    func testCloudDownloadRetriesThenImports() async throws {
        let source = try TemporaryDirectory()
        let roots = try Self.makeRoots()
        let fileURL = try source.write("cloud.m4a", bytes: 128)
        let downloader = FakeCloudDownloader(failuresBeforeSuccess: 1)

        let result = try await Self.importFolder(
            source: source.url,
            roots: roots,
            cloudDownloader: downloader,
            scanner: FakeFolderScanner(result: Self.scanResult(
                root: source.url,
                fileURL: fileURL,
                cloudState: .needsDownload
            )),
            retryCount: 1
        )

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(downloader.callCount, 2, "One retry should happen before success")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.importedFiles[0].destinationURL.path))
    }

    func testCloudDownloadFailureIsReportedAfterRetries() async throws {
        let source = try TemporaryDirectory()
        let roots = try Self.makeRoots()
        let fileURL = try source.write("offline.m4a", bytes: 128)
        let downloader = FakeCloudDownloader(failuresBeforeSuccess: 5)

        let result = try await Self.importFolder(
            source: source.url,
            roots: roots,
            cloudDownloader: downloader,
            scanner: FakeFolderScanner(result: Self.scanResult(
                root: source.url,
                fileURL: fileURL,
                cloudState: .needsDownload
            )),
            retryCount: 1
        )

        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(downloader.callCount, 2)
        XCTAssertEqual(result.failureIssues.first?.kind, .cloudDownloadFailed)
        XCTAssertTrue(result.failureIssues.first?.message.contains("iCloud") == true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: roots.media.path).count, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: roots.staging.path).count, 0)
    }

    private static func scanResult(
        root: URL,
        fileURL: URL,
        cloudState: CloudItemState,
        byteSize: Int64 = 128
    ) -> ScanResult {
        let file = ScannedFile(
            url: fileURL,
            relativePath: fileURL.lastPathComponent,
            byteSize: byteSize,
            kind: .audio,
            contentTypeIdentifier: "public.mpeg-4-audio",
            cloudState: cloudState
        )
        return ScanResult(
            rootURL: root,
            files: [file],
            issues: [],
            unsupportedFiles: [],
            truncated: false,
            totalCandidates: 1
        )
    }

    func testScannedSizeMismatchReportsCopyFailedAndImportsNothing() async throws {
        for scannedSize in [Int64(64), Int64(4096)] {
            let source = try TemporaryDirectory()
            let roots = try Self.makeRoots()
            let fileURL = try source.write("changing.m4a", bytes: 128)
            let recorder = ProgressRecorder()

            let result = try await Self.importFolder(
                source: source.url,
                roots: roots,
                scanner: FakeFolderScanner(result: Self.scanResult(
                    root: source.url,
                    fileURL: fileURL,
                    cloudState: .local,
                    byteSize: scannedSize
                )),
                progress: { recorder.append($0) }
            )

            XCTAssertEqual(result.importedCount, 0, "scanned \(scannedSize) bytes")
            XCTAssertEqual(result.duplicateCount, 0)
            XCTAssertEqual(result.failedCount, 1)
            XCTAssertEqual(result.failureIssues.first?.kind, .copyFailed)
            XCTAssertTrue(
                result.failureIssues.first?.message.contains("源文件在导入期间发生变化") == true,
                "scanned \(scannedSize) bytes"
            )
            XCTAssertEqual(result.copiedBytes, 0)
            XCTAssertEqual(recorder.last?.phase, .finished)
            XCTAssertEqual(recorder.last?.completedFiles, 1)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: roots.media.path).count, 0)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: roots.staging.path).count, 0)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: fileURL.path),
                "The engine must not delete the source; the coordinator owns it."
            )
        }
    }

    func testRelinkKeepsExistingFingerprintButImportsNewCopy() async throws {
        let source = try TemporaryDirectory()
        let roots = try Self.makeRoots()
        let fileURL = try source.write("relink.m4a", bytes: 128)
        let data = try Data(contentsOf: fileURL)
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let result = try await Self.importFolder(
            source: source.url,
            roots: roots,
            existing: [fingerprint],
            relink: [fingerprint]
        )

        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.relinkedCount, 1)
        XCTAssertTrue(result.importedFiles[0].isRelink)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.importedFiles[0].destinationURL.path))
    }

    func testInvalidProbeLeavesNoPartialFile() async throws {
        let source = try TemporaryDirectory()
        let roots = try Self.makeRoots()
        try source.write("bad.m4a", bytes: 64)

        let result = try await Self.importFolder(
            source: source.url,
            roots: roots,
            probe: FailingMediaProbe()
        )
        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: roots.media.path).count, 0)
    }

    /// Regression: staged files must keep their real extension. AVFoundation
    /// infers the container from the path extension, and a `.part` staging name
    /// made every real probe fail even though the bytes were valid.
    func testRealProbeImportsMediaFromStaging() async throws {
        let source = try TemporaryDirectory()
        let roots = try Self.makeRoots()
        try FileManager.default.copyItem(
            at: TestFixtures.audioURL,
            to: source.url.appendingPathComponent("Episode 001.m4a")
        )

        let result = try await Self.importFolder(
            source: source.url,
            roots: roots,
            probe: AVMediaProbe()
        )

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        let imported = try XCTUnwrap(result.importedFiles.first)
        XCTAssertEqual(imported.kind, .audio)
        XCTAssertEqual(imported.originalFileName, "Episode 001.m4a")
        XCTAssertGreaterThan(imported.durationSeconds ?? 0, 0)
        XCTAssertEqual(imported.fileExtension, "m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.destinationURL.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: roots.staging.path).count, 0)
    }
}

private final class CancellationTrigger: @unchecked Sendable {
    private let lock = NSLock()
    private let target: Int
    private var cancelAction: (@Sendable () -> Void)?
    private var didCancel = false

    init(cancelAfterCompletedFiles target: Int) {
        self.target = target
    }

    func setCancelAction(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        cancelAction = action
        lock.unlock()
    }

    func record(_ progress: ImportProgress) {
        lock.lock()
        let action = cancelAction
        let shouldCancel = progress.phase == .copying
            && progress.completedFiles >= target
            && !didCancel
        if shouldCancel { didCancel = true }
        lock.unlock()
        if shouldCancel {
            action?()
        }
    }
}
