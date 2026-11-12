import Foundation
import CryptoKit

/// Streaming SHA-256 for in-place imports. The copy pipeline hashes while it
/// copies; linked imports must hash the user's file without creating a copy,
/// and must not load a multi-hundred-MB file into memory.
public enum FileFingerprint {
    public enum Error: Swift.Error, LocalizedError {
        case cannotOpen(URL)
        case readFailed(URL)

        public var errorDescription: String? {
            switch self {
            case .cannotOpen(let url):
                LocalPodLocalization.format("error.fingerprint.open", url.lastPathComponent)
            case .readFailed(let url):
                LocalPodLocalization.format("error.fingerprint.read", url.lastPathComponent)
            }
        }
    }

    public static func sha256(of url: URL, chunkSize: Int = 1 << 20) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw Error.cannotOpen(url)
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
