import Foundation

public enum MediaStorageError: LocalizedError {
    case missingApplicationSupport
    case missingCaches
    case outsideApplicationSupport(URL)
    case invalidRelativePath(String)
    case cannotCreateDirectory(URL)

    public var errorDescription: String? {
        switch self {
        case .missingApplicationSupport:
            "无法定位 Application Support 目录。"
        case .missingCaches:
            "无法定位 Caches 目录。"
        case .outsideApplicationSupport(let url):
            "文件不在 Application Support 内：\(url.path)"
        case .invalidRelativePath(let path):
            "无效的相对路径：\(path)"
        case .cannotCreateDirectory(let url):
            "无法创建目录：\(url.path)"
        }
    }
}

public struct MediaStorage: Sendable {
    public let applicationSupportRoot: URL
    public let cachesRoot: URL

    public init(applicationSupportRoot: URL? = nil, cachesRoot: URL? = nil) throws {
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

        if let cachesRoot {
            self.cachesRoot = cachesRoot.standardizedFileURL
        } else {
            guard let root = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first else {
                throw MediaStorageError.missingCaches
            }
            self.cachesRoot = root.standardizedFileURL
        }
    }

    /// `Application Support/Media`. Media is excluded from iCloud backup.
    public func mediaRootURL() throws -> URL {
        let url = applicationSupportRoot
            .appendingPathComponent("Media", isDirectory: true)
            .standardizedFileURL
        try createDirectory(url)
        excludeFromBackup(url)
        return url
    }

    /// Staging lives on the same volume as the final media so committing a
    /// completed file is an atomic rename, not a cross-volume copy.
    public func stagingRootURL() throws -> URL {
        let url = applicationSupportRoot
            .appendingPathComponent("ImportStaging", isDirectory: true)
            .standardizedFileURL
        try createDirectory(url)
        excludeFromBackup(url)
        return url
    }

    public func newStagingSessionURL(id: UUID = UUID()) throws -> URL {
        let url = try stagingRootURL()
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try createDirectory(url)
        return url
    }

    public func mediaDestinationURL(id: UUID, fileExtension: String) throws -> URL {
        let root = try mediaRootURL()
        let ext = Self.safeExtension(fileExtension)
        let name = ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)"
        return root.appendingPathComponent(name, isDirectory: false)
    }

    /// Kept for the M0 spike/tests. New imports use `newStagingSessionURL`.
    public func newSessionURL(id: UUID = UUID()) throws -> URL {
        let url = try mediaRootURL()
            .appendingPathComponent("Imports", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try createDirectory(url)
        return url
    }

    public func artworkRootURL() throws -> URL {
        let url = cachesRoot
            .appendingPathComponent("Artwork", isDirectory: true)
            .standardizedFileURL
        try createDirectory(url)
        return url
    }

    public func artworkURL(forKey key: String) throws -> URL {
        let root = try artworkRootURL()
        let safe = PathSanitizer.sanitizeRelativePath(key)
        let candidate = root.appendingPathComponent(safe).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else {
            throw MediaStorageError.invalidRelativePath(key)
        }
        return candidate
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

    public func removeItemIfExists(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    public func removeArtwork(forKey key: String?) {
        guard let key, let url = try? artworkURL(forKey: key) else { return }
        removeItemIfExists(at: url)
    }

    private func createDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw MediaStorageError.cannotCreateDirectory(url)
        }
    }

    private func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    static func safeExtension(_ fileExtension: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let filtered = fileExtension.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(filtered)).lowercased()
    }

    public static let live: MediaStorage = {
        do {
            return try MediaStorage()
        } catch {
            fatalError("LocalPod 无法创建 MediaStorage：\(error)")
        }
    }()
}
