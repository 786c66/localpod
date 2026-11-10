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

public struct UnsupportedFile: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let relativePath: String
    public let contentTypeIdentifier: String?

    public init(id: UUID = UUID(), relativePath: String, contentTypeIdentifier: String?) {
        self.id = id
        self.relativePath = relativePath
        self.contentTypeIdentifier = contentTypeIdentifier
    }

    public var message: String {
        if let contentTypeIdentifier {
            "不支持的格式：\(contentTypeIdentifier)"
        } else {
            "不支持的格式"
        }
    }
}

public enum CloudItemState: String, Sendable, Hashable {
    case local
    case needsDownload

    public var needsDownload: Bool { self == .needsDownload }
}

public struct ScannedFile: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let url: URL
    public let relativePath: String
    public let byteSize: Int64
    public let kind: MediaKind
    public let contentTypeIdentifier: String?
    public let cloudState: CloudItemState

    public init(
        id: UUID = UUID(),
        url: URL,
        relativePath: String,
        byteSize: Int64,
        kind: MediaKind,
        contentTypeIdentifier: String?,
        cloudState: CloudItemState = .local
    ) {
        self.id = id
        self.url = url
        self.relativePath = relativePath
        self.byteSize = byteSize
        self.kind = kind
        self.contentTypeIdentifier = contentTypeIdentifier
        self.cloudState = cloudState
    }

    public var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }

    public var originalFileName: String {
        url.lastPathComponent
    }

    public var relativeFolderPath: String {
        let folder = (relativePath as NSString).deletingLastPathComponent
        return folder == "." ? "" : folder
    }
}

public struct ScanResult: Sendable {
    public let rootURL: URL
    public let files: [ScannedFile]
    public let issues: [ScanIssue]
    public let unsupportedFiles: [UnsupportedFile]
    public let truncated: Bool
    public let totalCandidates: Int
    public let totalBytes: Int64

    public var skippedUnsupportedCount: Int { unsupportedFiles.count }

    public init(
        rootURL: URL,
        files: [ScannedFile],
        issues: [ScanIssue],
        unsupportedFiles: [UnsupportedFile],
        truncated: Bool,
        totalCandidates: Int
    ) {
        self.rootURL = rootURL
        self.files = files
        self.issues = issues
        self.unsupportedFiles = unsupportedFiles
        self.truncated = truncated
        self.totalCandidates = totalCandidates
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

public protocol FolderScanning: Sendable {
    func scan(rootURL: URL, limits: FolderScanner.Limits) throws -> ScanResult
}

public struct FolderScanner: FolderScanning, Sendable {
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
                unsupportedFiles: [],
                truncated: false,
                totalCandidates: 1
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
        var unsupportedFiles: [UnsupportedFile] = []
        var totalCandidates = 0
        var truncated = false

        while let url = enumerator.nextObject() as? URL {
            if totalCandidates >= limits.maxFiles {
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

            totalCandidates += 1
            let relative = Self.relativePath(of: url, root: root)
            let contentType = values?.contentType

            guard let kind = SupportedMedia.kind(for: contentType) else {
                unsupportedFiles.append(UnsupportedFile(
                    relativePath: relative,
                    contentTypeIdentifier: contentType?.identifier
                ))
                continue
            }

            let cloudState: CloudItemState
            if values?.isUbiquitousItem == true,
               values?.ubiquitousItemDownloadingStatus != .current {
                cloudState = .needsDownload
            } else {
                cloudState = .local
            }

            let size = Int64(values?.fileSize ?? 0)
            files.append(ScannedFile(
                url: url,
                relativePath: relative,
                byteSize: size,
                kind: kind,
                contentTypeIdentifier: contentType?.identifier,
                cloudState: cloudState
            ))
        }

        files.sort {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }

        return ScanResult(
            rootURL: root,
            files: files,
            issues: issueBox.issues,
            unsupportedFiles: unsupportedFiles,
            truncated: truncated,
            totalCandidates: totalCandidates
        )
    }

    public func scannedFile(for url: URL, relativePath: String? = nil) throws -> ScannedFile {
        let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys))
        guard values?.isRegularFile == true else {
            throw FolderScannerError.notAFile(url)
        }
        guard let kind = SupportedMedia.kind(for: values?.contentType) else {
            throw FolderScannerError.notAFile(url)
        }
        let cloudState: CloudItemState
        if values?.isUbiquitousItem == true,
           values?.ubiquitousItemDownloadingStatus != .current {
            cloudState = .needsDownload
        } else {
            cloudState = .local
        }
        return ScannedFile(
            url: url,
            relativePath: relativePath ?? url.lastPathComponent,
            byteSize: Int64(values?.fileSize ?? 0),
            kind: kind,
            contentTypeIdentifier: values?.contentType?.identifier,
            cloudState: cloudState
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
