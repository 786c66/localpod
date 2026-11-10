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
    ///
    /// The copy lands in a hidden temporary item inside the inbox and is then
    /// atomically renamed to its final unique destination. Inbox scans skip
    /// hidden items, so a crash or failure can never expose a partial file as
    /// pending, and no partial destination is left behind.
    @discardableResult
    public func stage(url sourceURL: URL) throws -> URL {
        try ensureExists()
        let fileManager = FileManager.default
        let source = sourceURL.standardizedFileURL
        let inboxPrefix = directoryURL.path + "/"
        if source.path.hasPrefix(inboxPrefix) {
            return source
        }

        let temporaryURL = directoryURL.appendingPathComponent(
            ".localpod-stage-\(UUID().uuidString)",
            isDirectory: false
        )

        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: source,
            options: [],
            error: &coordinatorError
        ) { readURL in
            do {
                try fileManager.copyItem(at: readURL, to: temporaryURL)
            } catch {
                copyError = error
            }
        }

        if let coordinatorError {
            try? fileManager.removeItem(at: temporaryURL)
            throw coordinatorError
        }
        if let copyError {
            try? fileManager.removeItem(at: temporaryURL)
            throw copyError
        }

        var moveAttempts = 0
        while true {
            let destination = Self.uniqueDestination(
                for: source.lastPathComponent,
                in: directoryURL,
                fileManager: fileManager
            )
            do {
                try fileManager.moveItem(at: temporaryURL, to: destination)
                return destination
            } catch {
                // Another stage may have claimed the name after we checked.
                if fileManager.fileExists(atPath: destination.path), moveAttempts < 100 {
                    moveAttempts += 1
                    continue
                }
                try? fileManager.removeItem(at: temporaryURL)
                throw error
            }
        }
    }

    /// Removes hidden staging leftovers from a previous crash. Recent items
    /// are kept so a concurrent stage can finish; callers use this at launch.
    @discardableResult
    public func cleanupStaleStaging(olderThan age: TimeInterval = 3600) throws -> Int {
        try ensureExists()
        let cutoff = Date().addingTimeInterval(-max(0, age))
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        )
        var removed = 0
        for url in urls where url.lastPathComponent.hasPrefix(".localpod-stage-") {
            let modifiedAt = try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            if let modifiedAt, modifiedAt > cutoff { continue }
            try? FileManager.default.removeItem(at: url)
            removed += 1
        }
        return removed
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
