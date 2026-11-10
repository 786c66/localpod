import Foundation

public enum ImportPhase: String, Sendable {
    case idle
    case scanning
    case copying
    case finished
    case cancelled
    case failed

    public var displayName: String {
        switch self {
        case .idle: "空闲"
        case .scanning: "扫描中"
        case .copying: "复制中"
        case .finished: "完成"
        case .cancelled: "已取消"
        case .failed: "失败"
        }
    }
}

public struct ImportProgress: Sendable {
    public var phase: ImportPhase
    public var totalFiles: Int
    public var completedFiles: Int
    public var totalBytes: Int64
    public var copiedBytes: Int64
    public var currentFileName: String?
    public var currentFileBytes: Int64
    public var currentFileTotalBytes: Int64

    public init(
        phase: ImportPhase,
        totalFiles: Int = 0,
        completedFiles: Int = 0,
        totalBytes: Int64 = 0,
        copiedBytes: Int64 = 0,
        currentFileName: String? = nil,
        currentFileBytes: Int64 = 0,
        currentFileTotalBytes: Int64 = 0
    ) {
        self.phase = phase
        self.totalFiles = totalFiles
        self.completedFiles = completedFiles
        self.totalBytes = totalBytes
        self.copiedBytes = copiedBytes
        self.currentFileName = currentFileName
        self.currentFileBytes = currentFileBytes
        self.currentFileTotalBytes = currentFileTotalBytes
    }

    public var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(copiedBytes) / Double(totalBytes)))
    }
}

public struct ImportedFile: Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let destinationURL: URL
    public let sourceRelativePath: String
    public let byteSize: Int64
    public let kind: MediaKind
    public let displayName: String

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        destinationURL: URL,
        sourceRelativePath: String,
        byteSize: Int64,
        kind: MediaKind,
        displayName: String
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.sourceRelativePath = sourceRelativePath
        self.byteSize = byteSize
        self.kind = kind
        self.displayName = displayName
    }
}

public struct ImportRunResult: Sendable {
    public var importedFiles: [ImportedFile]
    public var issues: [ScanIssue]
    public var skippedUnsupportedCount: Int
    public var truncated: Bool
    public var totalBytes: Int64
    public var copiedBytes: Int64
    public var scanDuration: Duration?
    public var copyDuration: Duration?
    public var cancelled: Bool
    public var startedAt: Date
    public var finishedAt: Date

    public init(
        importedFiles: [ImportedFile],
        issues: [ScanIssue],
        skippedUnsupportedCount: Int,
        truncated: Bool,
        totalBytes: Int64,
        copiedBytes: Int64,
        scanDuration: Duration?,
        copyDuration: Duration?,
        cancelled: Bool,
        startedAt: Date,
        finishedAt: Date
    ) {
        self.importedFiles = importedFiles
        self.issues = issues
        self.skippedUnsupportedCount = skippedUnsupportedCount
        self.truncated = truncated
        self.totalBytes = totalBytes
        self.copiedBytes = copiedBytes
        self.scanDuration = scanDuration
        self.copyDuration = copyDuration
        self.cancelled = cancelled
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
