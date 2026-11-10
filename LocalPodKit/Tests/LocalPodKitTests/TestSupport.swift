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
