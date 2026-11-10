import CryptoKit
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

public struct CopyResult: Sendable {
    public let byteCount: Int64
    public let sha256: String

    public init(byteCount: Int64, sha256: String) {
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public struct ChunkedFileCopier: Sendable {
    public let chunkSize: Int
    /// Debug-only pacing hook used by UI tests that need an import to stay
    /// cancellable long enough to be interrupted.
    public let chunkDelay: Duration?

    public init(chunkSize: Int = 1 << 20, chunkDelay: Duration? = nil) {
        self.chunkSize = max(64 * 1024, chunkSize)
        self.chunkDelay = chunkDelay
    }

    /// Copies with bounded memory and calculates SHA-256 in the same pass.
    /// The destination is removed on error or cancellation so callers never
    /// leave a half-written file behind.
    public func copyHashing(
        from source: URL,
        to destination: URL,
        onChunk: @Sendable (Int64) -> Void = { _ in }
    ) async throws -> CopyResult {
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

        var hasher = SHA256()
        var copied: Int64 = 0
        do {
            while true {
                try Task.checkCancellation()
                guard let data = try input.read(upToCount: chunkSize), !data.isEmpty else {
                    break
                }
                try output.write(contentsOf: data)
                hasher.update(data: data)
                copied += Int64(data.count)
                onChunk(copied)
                if let chunkDelay, chunkDelay > .zero {
                    try await Task.sleep(for: chunkDelay)
                }
            }
            try output.synchronize()
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return CopyResult(byteCount: copied, sha256: digest)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    /// Backwards-compatible convenience for callers that do not need the hash.
    @discardableResult
    public func copy(
        from source: URL,
        to destination: URL,
        onChunk: @Sendable (Int64) -> Void = { _ in }
    ) async throws -> Int64 {
        try await copyHashing(from: source, to: destination, onChunk: onChunk).byteCount
    }
}
