import Darwin
import Foundation
import SwiftData
import XCTest
@testable import LocalPodKit

@MainActor
final class FiveThousandImportTests: XCTestCase {
    func testFiveThousandFileImportStaysUnder200MB() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for index in 0..<5_000 {
            let directory = source
                .appendingPathComponent("Season \(index / 100 + 1)", isDirectory: true)
                .appendingPathComponent("Disc \(index / 20 % 5 + 1)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = Data("fixture-\(index)-".utf8) + Data(repeating: UInt8(index % 251), count: 512)
            try data.write(to: directory.appendingPathComponent(String(format: "Episode %05d.m4a", index)))
        }

        let storage = try MediaStorage(
            applicationSupportRoot: root.url.appendingPathComponent("Support"),
            cachesRoot: root.url.appendingPathComponent("Caches")
        )
        let library = LibraryService(storage: storage)
        let service = FolderImportService(storage: storage, library: library)
        let container = try LocalPodStore.makeContainer(inMemory: true)
        let context = container.mainContext

        let sampler = MemorySampler()
        let baseline = sampler.currentBytes
        let result = try await service.importFolder(
            rootURL: source,
            source: .files,
            rootName: "5000 Files",
            in: context,
            probe: FakeMediaProbe(),
            progress: { _ in sampler.record() }
        )
        sampler.record()

        let peakDelta = sampler.peakBytes > baseline ? sampler.peakBytes - baseline : 0
        print(String(
            format: "5000-file import: %.1f MB peak delta, %.1f MB final delta",
            Double(peakDelta) / 1_048_576,
            Double(sampler.currentBytes - baseline) / 1_048_576
        ))

        XCTAssertEqual(result.report.importedCount, 5_000)
        XCTAssertEqual(result.report.failedCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MediaItem>()), 5_000)
        XCTAssertLessThan(peakDelta, 200 * 1_048_576)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: try storage.stagingRootURL().path).count,
            0
        )
    }
}

private final class MemorySampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64 = 0

    init() {
        peak = currentBytes
    }

    var currentBytes: UInt64 {
        Self.footprintBytes()
    }

    var peakBytes: UInt64 {
        lock.withLock { peak }
    }

    func record() {
        let value = Self.footprintBytes()
        lock.withLock {
            peak = max(peak, value)
        }
    }

    private static func footprintBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.resident_size
    }
}
