import Foundation
import UniformTypeIdentifiers

public struct ScanIssue: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let relativePath: String
    public let message: String

    public init(id: UUID = UUID(), relativePath: String, message: String) {
        self.id = id
        self.relativePath = relativePath
        self.message = message
    }
}

public struct ScannedFile: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let url: URL
    public let relativePath: String
    public let byteSize: Int64
    public let kind: MediaKind
    public let contentTypeIdentifier: String?

    public init(
        id: UUID = UUID(),
        url: URL,
        relativePath: String,
        byteSize: Int64,
        kind: MediaKind,
        contentTypeIdentifier: String?
    ) {
        self.id = id
        self.url = url
        self.relativePath = relativePath
        self.byteSize = byteSize
        self.kind = kind
        self.contentTypeIdentifier = contentTypeIdentifier
    }

    public var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }
}

public struct ScanResult: Sendable {
    public let rootURL: URL
    public let files: [ScannedFile]
    public let issues: [ScanIssue]
    public let skippedUnsupportedCount: Int
    public let truncated: Bool
    public let totalBytes: Int64

    public init(
        rootURL: URL,
        files: [ScannedFile],
        issues: [ScanIssue],
        skippedUnsupportedCount: Int,
        truncated: Bool
    ) {
        self.rootURL = rootURL
        self.files = files
        self.issues = issues
        self.skippedUnsupportedCount = skippedUnsupportedCount
        self.truncated = truncated
        self.totalBytes = files.reduce(into: Int64(0)) { partial, file in
            partial += file.byteSize
        }
    }
}

public enum FolderScannerError: LocalizedError {
    case cannotEnumerate(URL)
    case notAFile(URL)

    public var errorDescription: String? {
        switch self {
        case .cannotEnumerate(let url):
            "无法枚举文件夹：\(url.path)"
        case .notAFile(let url):
            "不是可导入的文件：\(url.path)"
        }
    }
}

public struct FolderScanner: Sendable {
    public struct Limits: Sendable {
        public var maxDepth: Int
        public var maxFiles: Int

        public init(maxDepth: Int = 32, maxFiles: Int = 20_000) {
            self.maxDepth = max(1, maxDepth)
            self.maxFiles = max(1, maxFiles)
        }
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .fileSizeKey,
        .contentTypeKey,
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey
    ]

    public init() {}

    public func scan(rootURL: URL, limits: Limits = Limits()) throws -> ScanResult {
        let isDirectory = (try? rootURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if !isDirectory {
            let file = try scannedFile(for: rootURL, relativePath: rootURL.lastPathComponent)
            return ScanResult(
                rootURL: rootURL.deletingLastPathComponent(),
                files: [file],
                issues: [],
                skippedUnsupportedCount: 0,
                truncated: false
            )
        }

        let root = rootURL.standardizedFileURL
        let issueBox = IssueBox()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Self.resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                issueBox.append(ScanIssue(
                    relativePath: Self.relativePath(of: url, root: root),
                    message: error.localizedDescription
                ))
                return true
            }
        ) else {
            throw FolderScannerError.cannotEnumerate(root)
        }

        var files: [ScannedFile] = []
        var skippedUnsupported = 0
        var truncated = false

        while let url = enumerator.nextObject() as? URL {
            if files.count >= limits.maxFiles {
                truncated = true
                break
            }
            if enumerator.level > limits.maxDepth {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys))
            if values?.isSymbolicLink == true { continue }
            if values?.isDirectory == true { continue }
            guard values?.isRegularFile == true else { continue }

            let relative = Self.relativePath(of: url, root: root)
            if values?.isUbiquitousItem == true {
                let status = values?.ubiquitousItemDownloadingStatus
                if status != .current {
                    issueBox.append(ScanIssue(
                        relativePath: relative,
                        message: "iCloud 文件尚未下载，M0 先跳过。"
                    ))
                    continue
                }
            }

            guard let kind = SupportedMedia.kind(for: values?.contentType) else {
                skippedUnsupported += 1
                continue
            }

            let size = Int64(values?.fileSize ?? 0)
            files.append(ScannedFile(
                url: url,
                relativePath: relative,
                byteSize: size,
                kind: kind,
                contentTypeIdentifier: values?.contentType?.identifier
            ))
        }

        files.sort {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }

        return ScanResult(
            rootURL: root,
            files: files,
            issues: issueBox.issues,
            skippedUnsupportedCount: skippedUnsupported,
            truncated: truncated
        )
    }

    public func scannedFile(for url: URL, relativePath: String? = nil) throws -> ScannedFile {
        let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys))
        guard values?.isRegularFile == true else {
            throw FolderScannerError.notAFile(url)
        }
        if values?.isUbiquitousItem == true,
           values?.ubiquitousItemDownloadingStatus != .current {
            throw FolderScannerError.notAFile(url)
        }
        guard let kind = SupportedMedia.kind(for: values?.contentType) else {
            throw FolderScannerError.notAFile(url)
        }
        return ScannedFile(
            url: url,
            relativePath: relativePath ?? url.lastPathComponent,
            byteSize: Int64(values?.fileSize ?? 0),
            kind: kind,
            contentTypeIdentifier: values?.contentType?.identifier
        )
    }

    private static func relativePath(of url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let fullPath = url.standardizedFileURL.path
        guard fullPath.hasPrefix(rootPath + "/") else {
            return url.lastPathComponent
        }
        return String(fullPath.dropFirst(rootPath.count + 1))
    }
}

private final class IssueBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ScanIssue] = []

    func append(_ issue: ScanIssue) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(issue)
    }

    var issues: [ScanIssue] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
