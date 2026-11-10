import Foundation
import SwiftData

public struct FolderImportResult: Sendable {
    public let report: ImportRunResult
    public let commit: LibraryCommitResult
    public let reportPath: String?

    public init(
        report: ImportRunResult,
        commit: LibraryCommitResult,
        reportPath: String?
    ) {
        self.report = report
        self.commit = commit
        self.reportPath = reportPath
    }
}

private struct StoredImportIssue: Codable, Sendable {
    let relativePath: String
    let kind: String
    let message: String
}

private struct StoredImportReport: Codable, Sendable {
    let sessionID: UUID
    let source: String
    let rootName: String
    let startedAt: Date
    let finishedAt: Date
    let totalCandidates: Int
    let supportedFiles: Int
    let importedCount: Int
    let relinkedCount: Int
    let duplicateCount: Int
    let unsupportedCount: Int
    let failedCount: Int
    let totalBytes: Int64
    let copiedBytes: Int64
    let cancelled: Bool
    let duplicates: [StoredImportIssue]
    let unsupported: [StoredImportIssue]
    let failures: [StoredImportIssue]
}

/// Owns the end-to-end import: fingerprints from SwiftData → engine →
/// collection/item commit → JSON report → ImportSession record.
@MainActor
public final class FolderImportService {
    public let storage: MediaStorage
    public let library: LibraryService
    private let engine: ImportEngine

    public init(
        storage: MediaStorage = .live,
        library: LibraryService? = nil,
        engine: ImportEngine = ImportEngine()
    ) {
        self.storage = storage
        self.library = library ?? LibraryService(storage: storage)
        self.engine = engine
    }

    public func importFolder(
        rootURL: URL,
        source: MediaSource,
        rootName: String,
        collectionName: String? = nil,
        in context: ModelContext,
        options: ImportEngine.Options = ImportEngine.Options(),
        probe: any MediaProbing = AVMediaProbe(),
        cloudDownloader: any CloudDownloading = ICloudDownloader(),
        progress: @escaping @Sendable (ImportProgress) -> Void = { _ in }
    ) async throws -> FolderImportResult {
        let existingFingerprints = try library.fingerprints(in: context)
        let relinkFingerprints = try library.missingFingerprints(in: context)
        let sessionID = UUID()
        let stagingRoot = try storage.stagingRootURL()
        let mediaRoot = try storage.mediaRootURL()
        let artworkRoot = try storage.artworkRootURL()

        let report = try await engine.importFolder(
            rootURL: rootURL,
            source: source,
            rootName: rootName,
            sessionID: sessionID,
            stagingRootURL: stagingRoot,
            mediaRootURL: mediaRoot,
            artworkRootURL: artworkRoot,
            existingFingerprints: existingFingerprints,
            relinkFingerprints: relinkFingerprints,
            options: options,
            probe: probe,
            cloudDownloader: cloudDownloader,
            progress: progress
        )

        let commit = try library.commit(
            report: report,
            collectionName: collectionName ?? rootName,
            in: context
        )

        let reportPath = writeReport(report)
        let session = ImportSession(
            id: report.sessionID,
            startedAt: report.startedAt,
            endedAt: report.finishedAt,
            source: report.source,
            rootName: report.rootName,
            totalCandidates: report.totalCandidates,
            supportedFiles: report.supportedFiles,
            totalBytes: report.totalBytes,
            importedCount: report.importedCount,
            duplicateCount: report.duplicateCount,
            unsupportedCount: report.unsupportedCount,
            failedCount: report.failedCount,
            relinkedCount: report.relinkedCount,
            cancelled: report.cancelled,
            reportPath: reportPath,
            status: report.status
        )
        context.insert(session)
        try context.save()

        return FolderImportResult(
            report: report,
            commit: commit,
            reportPath: reportPath
        )
    }

    private func writeReport(_ report: ImportRunResult) -> String? {
        let fileManager = FileManager.default
        let directory = storage.applicationSupportRoot
            .appendingPathComponent("ImportReports", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let name = "\(formatter.string(from: report.startedAt))-\(report.sessionID.uuidString).json"
            let url = directory.appendingPathComponent(name)

            let stored = StoredImportReport(
                sessionID: report.sessionID,
                source: report.source.rawValue,
                rootName: report.rootName,
                startedAt: report.startedAt,
                finishedAt: report.finishedAt,
                totalCandidates: report.totalCandidates,
                supportedFiles: report.supportedFiles,
                importedCount: report.importedCount,
                relinkedCount: report.relinkedCount,
                duplicateCount: report.duplicateCount,
                unsupportedCount: report.unsupportedCount,
                failedCount: report.failedCount,
                totalBytes: report.totalBytes,
                copiedBytes: report.copiedBytes,
                cancelled: report.cancelled,
                duplicates: report.duplicateIssues.map {
                    StoredImportIssue(
                        relativePath: $0.relativePath,
                        kind: $0.kind.rawValue,
                        message: $0.message
                    )
                },
                unsupported: report.unsupportedIssues.map {
                    StoredImportIssue(
                        relativePath: $0.relativePath,
                        kind: $0.kind.rawValue,
                        message: $0.message
                    )
                },
                failures: report.failureIssues.map {
                    StoredImportIssue(
                        relativePath: $0.relativePath,
                        kind: $0.kind.rawValue,
                        message: $0.message
                    )
                }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(stored).write(to: url, options: .atomic)
            return try storage.relativePath(for: url)
        } catch {
            return nil
        }
    }
}
