import Foundation

public enum ChunkedFileCopierError: LocalizedError {
    case cannotCreateDestination(URL)

    public var errorDescription: String? {
        switch self {
        case .cannotCreateDestination(let url):
            "无法创建目标文件：\(url.path)"
        }
    }
}

public struct ChunkedFileCopier: Sendable {
    public let chunkSize: Int

    public init(chunkSize: Int = 1 << 20) {
        self.chunkSize = max(64 * 1024, chunkSize)
    }

    /// Copies with bounded memory and reports bytes written for this file.
    /// The destination is removed on error or cancellation so callers never
    /// leave a half-written file behind.
    @discardableResult
    public func copy(
        from source: URL,
        to destination: URL,
        onChunk: @Sendable (Int64) -> Void = { _ in }
    ) throws -> Int64 {
        let fileManager = FileManager.default
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw ChunkedFileCopierError.cannotCreateDestination(destination)
        }

        let input: FileHandle
        do {
            input = try FileHandle(forReadingFrom: source)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }

        let output: FileHandle
        do {
            output = try FileHandle(forWritingTo: destination)
        } catch {
            try? input.close()
            try? fileManager.removeItem(at: destination)
            throw error
        }

        defer {
            try? input.close()
            try? output.close()
        }

        var copied: Int64 = 0
        do {
            while true {
                try Task.checkCancellation()
                guard let data = try input.read(upToCount: chunkSize), !data.isEmpty else {
                    break
                }
                try output.write(contentsOf: data)
                copied += Int64(data.count)
                onChunk(copied)
            }
            try output.synchronize()
            return copied
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }
}
