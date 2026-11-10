import Foundation
import SwiftData
import XCTest
@testable import LocalPodKit

@MainActor
final class SwiftDataBenchmarkTests: XCTestCase {
    func testInsertAndQueryFiveThousandItems() throws {
        let container = try LocalPodStore.makeContainer(inMemory: true)
        let context = container.mainContext

        let insertStart = Date()
        for index in 0..<5_000 {
            context.insert(MediaItem(
                title: "Benchmark \(index)",
                relativePath: "benchmark/\(index)",
                kind: index.isMultiple(of: 2) ? .audio : .video,
                fileExtension: index.isMultiple(of: 2) ? "m4a" : "mp4",
                byteSize: Int64(index),
                folderName: "benchmark",
                source: .benchmark
            ))
        }
        try context.save()
        let insertDuration = Date().timeIntervalSince(insertStart)

        let countStart = Date()
        let predicate = #Predicate<MediaItem> { $0.sourceRaw == "benchmark" }
        let count = try context.fetchCount(FetchDescriptor<MediaItem>(predicate: predicate))
        var descriptor = FetchDescriptor<MediaItem>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        let page = try context.fetch(descriptor)
        let queryDuration = Date().timeIntervalSince(countStart)

        XCTAssertEqual(count, 5_000)
        XCTAssertEqual(page.count, 100)
        print(String(
            format: "SwiftData benchmark (macOS, in-memory): insert %.3fs, count+page %.3fs",
            insertDuration,
            queryDuration
        ))
    }
}
