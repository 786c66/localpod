import Foundation

public enum ImportInboxError: LocalizedError {
    case missingDocumentsDirectory

    public var errorDescription: String? {
        switch self {
        case .missingDocumentsDirectory:
            "无法定位 Documents 目录。"
        }
    }
}

/// `Documents/Import` is the only user-visible part of Documents. Media and
/// the SwiftData store live in Application Support.
public struct ImportInbox: Sendable {
    public let documentsRoot: URL

    public init(documentsRoot: URL? = nil) throws {
        if let documentsRoot {
            self.documentsRoot = documentsRoot.standardizedFileURL
        } else {
            guard let root = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first else {
                throw ImportInboxError.missingDocumentsDirectory
            }
            self.documentsRoot = root.standardizedFileURL
        }
    }

    public var directoryURL: URL {
        documentsRoot.appendingPathComponent("Import", isDirectory: true)
    }

    @discardableResult
    public func ensureExists() throws -> URL {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL
    }

    public func pendingURLs() throws -> [URL] {
        try ensureExists()
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentTypeKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        return urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// Copies a file or folder into the inbox. The caller must hold any
    /// security-scoped access for the duration of this call.
    @discardableResult
    public func stage(url sourceURL: URL) throws -> URL {
        try ensureExists()
        let fileManager = FileManager.default
        let source = sourceURL.standardizedFileURL
        let inboxPrefix = directoryURL.path + "/"
        if source.path.hasPrefix(inboxPrefix) {
            return source
        }

        let destination = Self.uniqueDestination(
            for: source.lastPathComponent,
            in: directoryURL,
            fileManager: fileManager
        )

        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: source,
            options: [],
            error: &coordinatorError
        ) { readURL in
            do {
                try fileManager.copyItem(at: readURL, to: destination)
            } catch {
                copyError = error
            }
        }

        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        return destination
    }

    public func remove(_ url: URL) throws {
        let standardized = url.standardizedFileURL
        guard standardized.path.hasPrefix(directoryURL.path + "/") else {
            return
        }
        try FileManager.default.removeItem(at: standardized)
    }

    private static func uniqueDestination(
        for name: String,
        in directory: URL,
        fileManager: FileManager
    ) -> URL {
        let safeName = PathSanitizer.sanitizeRelativePath(name)
        let base = directory.appendingPathComponent(safeName)
        guard fileManager.fileExists(atPath: base.path) else { return base }

        let ext = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    public static let live: ImportInbox = {
        do {
            return try ImportInbox()
        } catch {
            fatalError("LocalPod 无法创建 ImportInbox：\(error)")
        }
    }()
}
