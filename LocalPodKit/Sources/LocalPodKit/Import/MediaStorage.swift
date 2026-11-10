import Foundation

public enum MediaStorageError: LocalizedError {
    case missingApplicationSupport
    case outsideApplicationSupport(URL)
    case invalidRelativePath(String)

    public var errorDescription: String? {
        switch self {
        case .missingApplicationSupport:
            "无法定位 Application Support 目录。"
        case .outsideApplicationSupport(let url):
            "文件不在 Application Support 内：\(url.path)"
        case .invalidRelativePath(let path):
            "无效的相对路径：\(path)"
        }
    }
}

public struct MediaStorage: Sendable {
    public let applicationSupportRoot: URL

    public init(applicationSupportRoot: URL? = nil) throws {
        if let applicationSupportRoot {
            self.applicationSupportRoot = applicationSupportRoot.standardizedFileURL
        } else {
            guard let root = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw MediaStorageError.missingApplicationSupport
            }
            self.applicationSupportRoot = root.standardizedFileURL
        }
    }

    /// `Application Support/Media`. Media is excluded from iCloud backup.
    public func mediaRootURL() throws -> URL {
        let url = applicationSupportRoot
            .appendingPathComponent("Media", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
        return url
    }

    /// A fresh import directory. Each import session gets its own folder so a
    /// cancelled session can be cleaned up without touching earlier imports.
    public func newSessionURL(id: UUID = UUID()) throws -> URL {
        let url = try mediaRootURL()
            .appendingPathComponent("Imports", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func relativePath(for url: URL) throws -> String {
        let base = applicationSupportRoot.path
        let full = url.standardizedFileURL.path
        guard full.hasPrefix(base + "/") else {
            throw MediaStorageError.outsideApplicationSupport(url)
        }
        return String(full.dropFirst(base.count + 1))
    }

    public func url(forRelativePath path: String) throws -> URL {
        let sanitized = PathSanitizer.sanitizeRelativePath(path)
        guard !sanitized.isEmpty else {
            throw MediaStorageError.invalidRelativePath(path)
        }
        let candidate = applicationSupportRoot
            .appendingPathComponent(sanitized)
            .standardizedFileURL
        guard candidate.path.hasPrefix(applicationSupportRoot.path + "/") else {
            throw MediaStorageError.invalidRelativePath(path)
        }
        return candidate
    }

    public static let live: MediaStorage = {
        do {
            return try MediaStorage()
        } catch {
            fatalError("LocalPod 无法创建 MediaStorage：\(error)")
        }
    }()
}
