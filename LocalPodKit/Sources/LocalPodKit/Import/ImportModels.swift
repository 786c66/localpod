import Foundation

public enum ImportPhase: String, Sendable {
    case idle
    case scanning
    case downloading
    case copying
    case probing
    case finished
    case cancelled
    case failed

    public var displayName: String {
        displayName(locale: nil)
    }

    public func displayName(locale: Locale?) -> String {
        switch self {
        case .idle: LocalPodLocalization.string("import.phase.idle", locale: locale)
        case .scanning: LocalPodLocalization.string("import.phase.scanning", locale: locale)
        case .downloading: LocalPodLocalization.string("import.phase.downloading", locale: locale)
        case .copying: LocalPodLocalization.string("import.phase.copying", locale: locale)
        case .probing: LocalPodLocalization.string("import.phase.probing", locale: locale)
        case .finished: LocalPodLocalization.string("import.phase.finished", locale: locale)
        case .cancelled: LocalPodLocalization.string("import.phase.cancelled", locale: locale)
        case .failed: LocalPodLocalization.string("import.phase.failed", locale: locale)
        }
    }
}

public struct ImportProgress: Sendable {
    public var phase: ImportPhase
    /// All candidate files, including unsupported files. This keeps "100/100"
    /// meaningful even when a folder contains files LocalPod cannot play.
    public var totalFiles: Int
    public var completedFiles: Int
    public var totalBytes: Int64
    public var copiedBytes: Int64
    public var currentFileName: String?
    public var currentFileBytes: Int64
    public var currentFileTotalBytes: Int64
    public var currentFileDownloadFraction: Double?

    public init(
        phase: ImportPhase,
        totalFiles: Int = 0,
        completedFiles: Int = 0,
        totalBytes: Int64 = 0,
        copiedBytes: Int64 = 0,
        currentFileName: String? = nil,
        currentFileBytes: Int64 = 0,
        currentFileTotalBytes: Int64 = 0,
        currentFileDownloadFraction: Double? = nil
    ) {
        self.phase = phase
        self.totalFiles = totalFiles
        self.completedFiles = completedFiles
        self.totalBytes = totalBytes
        self.copiedBytes = copiedBytes
        self.currentFileName = currentFileName
        self.currentFileBytes = currentFileBytes
        self.currentFileTotalBytes = currentFileTotalBytes
        self.currentFileDownloadFraction = currentFileDownloadFraction
    }

    public var fractionCompleted: Double {
        if totalFiles > 0 {
            return min(1, max(0, Double(completedFiles) / Double(totalFiles)))
        }
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(copiedBytes) / Double(totalBytes)))
    }
}

public enum ImportIssueKind: String, Sendable, CaseIterable {
    case unsupported
    case duplicate
    case copyFailed
    case probeFailed
    case cloudDownloadFailed
    case moveFailed
    case scanError
    case databaseFailed
    case other

    public var displayName: String {
        displayName(locale: nil)
    }

    public func displayName(locale: Locale?) -> String {
        switch self {
        case .unsupported: LocalPodLocalization.string("import.issue.unsupported", locale: locale)
        case .duplicate: LocalPodLocalization.string("import.issue.duplicate", locale: locale)
        case .copyFailed: LocalPodLocalization.string("import.issue.copyFailed", locale: locale)
        case .probeFailed: LocalPodLocalization.string("import.issue.probeFailed", locale: locale)
        case .cloudDownloadFailed:
            LocalPodLocalization.string("import.issue.cloudDownloadFailed", locale: locale)
        case .moveFailed: LocalPodLocalization.string("import.issue.moveFailed", locale: locale)
        case .scanError: LocalPodLocalization.string("import.issue.scanError", locale: locale)
        case .databaseFailed: LocalPodLocalization.string("import.issue.databaseFailed", locale: locale)
        case .other: LocalPodLocalization.string("import.issue.other", locale: locale)
        }
    }
}

public struct ImportIssue: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let relativePath: String
    public let kind: ImportIssueKind
    public let message: String

    public init(
        id: UUID = UUID(),
        relativePath: String,
        kind: ImportIssueKind,
        message: String
    ) {
        self.id = id
        self.relativePath = relativePath
        self.kind = kind
        self.message = message
    }
}

public struct ImportedFile: Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let destinationURL: URL
    public let sourceRelativePath: String
    public let relativeFolderPath: String
    public let title: String
    public let originalFileName: String
    public let fileExtension: String
    public let byteSize: Int64
    public let kind: MediaKind
    public let durationSeconds: Double?
    public let fingerprint: String
    public let artworkKey: String?
    public let isRelink: Bool

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        destinationURL: URL,
        sourceRelativePath: String,
        relativeFolderPath: String,
        title: String,
        originalFileName: String,
        fileExtension: String,
        byteSize: Int64,
        kind: MediaKind,
        durationSeconds: Double?,
        fingerprint: String,
        artworkKey: String?,
        isRelink: Bool = false
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.sourceRelativePath = sourceRelativePath
        self.relativeFolderPath = relativeFolderPath
        self.title = title
        self.originalFileName = originalFileName
        self.fileExtension = fileExtension
        self.byteSize = byteSize
        self.kind = kind
        self.durationSeconds = durationSeconds
        self.fingerprint = fingerprint
        self.artworkKey = artworkKey
        self.isRelink = isRelink
    }

    public var displayName: String {
        (originalFileName as NSString).deletingPathExtension
    }
}

public struct ImportRunResult: Sendable {
    public var sessionID: UUID
    public var source: MediaSource
    public var rootName: String
    public var importedFiles: [ImportedFile]
    public var duplicateIssues: [ImportIssue]
    public var unsupportedIssues: [ImportIssue]
    public var failureIssues: [ImportIssue]
    public var scanIssues: [ScanIssue]
    public var truncated: Bool
    public var totalCandidates: Int
    public var supportedFiles: Int
    public var totalBytes: Int64
    public var copiedBytes: Int64
    public var scanDuration: Duration?
    public var copyDuration: Duration?
    public var cancelled: Bool
    public var startedAt: Date
    public var finishedAt: Date

    public init(
        sessionID: UUID,
        source: MediaSource,
        rootName: String,
        importedFiles: [ImportedFile],
        duplicateIssues: [ImportIssue],
        unsupportedIssues: [ImportIssue],
        failureIssues: [ImportIssue],
        scanIssues: [ScanIssue],
        truncated: Bool,
        totalCandidates: Int,
        supportedFiles: Int,
        totalBytes: Int64,
        copiedBytes: Int64,
        scanDuration: Duration?,
        copyDuration: Duration?,
        cancelled: Bool,
        startedAt: Date,
        finishedAt: Date
    ) {
        self.sessionID = sessionID
        self.source = source
        self.rootName = rootName
        self.importedFiles = importedFiles
        self.duplicateIssues = duplicateIssues
        self.unsupportedIssues = unsupportedIssues
        self.failureIssues = failureIssues
        self.scanIssues = scanIssues
        self.truncated = truncated
        self.totalCandidates = totalCandidates
        self.supportedFiles = supportedFiles
        self.totalBytes = totalBytes
        self.copiedBytes = copiedBytes
        self.scanDuration = scanDuration
        self.copyDuration = copyDuration
        self.cancelled = cancelled
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var importedCount: Int { importedFiles.filter { !$0.isRelink }.count }
    public var relinkedCount: Int { importedFiles.filter(\.isRelink).count }
    public var duplicateCount: Int { duplicateIssues.count }
    public var unsupportedCount: Int { unsupportedIssues.count }
    public var failedCount: Int { failureIssues.count }

    public var allIssues: [ImportIssue] {
        duplicateIssues + unsupportedIssues + failureIssues
    }

    public var status: ImportSessionStatus {
        if cancelled { return .cancelled }
        if importedCount == 0, relinkedCount == 0, failedCount > 0 { return .failed }
        return .finished
    }
}
