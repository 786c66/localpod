import Foundation
import Observation
import SwiftData
import LocalPodKit
#if os(iOS)
import UIKit
#endif

@MainActor
@Observable
final class ImportCoordinator {
    enum RunKind: String, Sendable {
        case folder = "文件夹"
        case demo = "演示文件夹"
        case acceptance = "验收文件夹"
        case inbox = "收件箱"
        case openURL = "外部打开"

        var displayName: String { rawValue }
    }

    struct RunSummary: Sendable {
        var kind: RunKind
        var collectionName: String
        var totalCandidates: Int
        var supportedFiles: Int
        var importedCount: Int
        var relinkedCount: Int
        var duplicateCount: Int
        var unsupportedCount: Int
        var failedCount: Int
        var copiedBytes: Int64
        var duration: TimeInterval
        var cancelled: Bool
        var messages: [String]
        var reportPath: String?
    }

    private(set) var phase: ImportPhase = .idle
    private(set) var progress: ImportProgress?
    private(set) var summary: RunSummary?
    private(set) var lastResult: FolderImportResult?
    private(set) var issueMessages: [String] = []
    private(set) var isRunning = false
    private(set) var isCancelling = false
    private(set) var currentKind: RunKind?
    private(set) var lastErrorMessage: String?
    private(set) var inboxPendingCount = 0
    private(set) var lastCleanupSummary: LibraryCleanupSummary?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private let storage = MediaStorage.live
    @ObservationIgnored private let inbox = ImportInbox.live
    @ObservationIgnored private let libraryService = LibraryService(storage: .live)
    @ObservationIgnored private lazy var importService = FolderImportService(
        storage: storage,
        library: libraryService
    )

    func bootstrap(modelContext: ModelContext) {
        do {
            try inbox.ensureExists()
            refreshInboxPendingCount()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        guard !didBootstrap else { return }
        didBootstrap = true
        runMaintenance(modelContext: modelContext)
        importInboxIfNeeded(modelContext: modelContext)
    }

    func runMaintenance(modelContext: ModelContext) {
        guard !isRunning else { return }
        do {
            let summary = try libraryService.reconcile(in: modelContext)
            lastCleanupSummary = lastCleanupSummary.map { $0.merging(summary) } ?? summary
        } catch {
            lastErrorMessage = "启动清理失败：\(error.localizedDescription)"
        }
    }

    func refreshInboxPendingCount() {
        inboxPendingCount = (try? inbox.pendingURLs().count) ?? 0
    }

    func importInboxIfNeeded(modelContext: ModelContext) {
        refreshInboxPendingCount()
        guard !isRunning else { return }
        guard let pending = try? inbox.pendingURLs(), !pending.isEmpty else { return }
        startInboxImport(pending, kind: .inbox, modelContext: modelContext)
    }

    func startFolderImport(_ url: URL, modelContext: ModelContext) {
        guard !isRunning else { return }
        startPreparedFolderImport(
            url,
            kind: .folder,
            source: .files,
            collectionName: url.lastPathComponent,
            modelContext: modelContext
        )
    }

    func importDemoFolder(modelContext: ModelContext) {
        importBuiltInFolder(
            kind: .demo,
            collectionName: "演示文件夹",
            acceptance: false,
            modelContext: modelContext
        )
    }

    func importAcceptanceFolder(modelContext: ModelContext) {
        importBuiltInFolder(
            kind: .acceptance,
            collectionName: "验收文件夹",
            acceptance: true,
            modelContext: modelContext
        )
    }

    private func importBuiltInFolder(
        kind: RunKind,
        collectionName: String,
        acceptance: Bool,
        modelContext: ModelContext
    ) {
        guard !isRunning else { return }
        guard let template = Bundle.main.url(forResource: "demo-audio", withExtension: "m4a") else {
            phase = .failed
            lastErrorMessage = "找不到内置演示音频 demo-audio.m4a。"
            return
        }
        let folderName = acceptance ? "AcceptanceInput" : "DemoInput"
        let demoRoot = storage.applicationSupportRoot
            .appendingPathComponent(folderName, isDirectory: true)
        beginRun(kind: kind)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let root = try await Task.detached(priority: .userInitiated) {
                    if acceptance {
                        return try DemoFolderFactory.makeAcceptanceFolderIfNeeded(
                            at: demoRoot,
                            audioTemplateURL: template
                        )
                    }
                    return try DemoFolderFactory.makeIfNeeded(
                        at: demoRoot,
                        audioTemplateURL: template
                    )
                }.value
                await self.runFolder(
                    rootURL: root,
                    kind: kind,
                    source: .imported,
                    collectionName: collectionName,
                    removeSourceAfterSuccess: false,
                    modelContext: modelContext
                )
            } catch {
                self.finishWithError(error)
            }
        }
    }

    func stageAndImportFile(_ url: URL, kind: RunKind = .openURL, modelContext: ModelContext) {
        guard !isRunning else {
            lastErrorMessage = "已有导入任务在进行，请稍后再试。"
            return
        }
        guard url.isFileURL else { return }
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let staged = try inbox.stage(url: url)
            refreshInboxPendingCount()
            startInboxImport([staged], kind: kind, modelContext: modelContext)
        } catch {
            phase = .failed
            lastErrorMessage = "无法放入收件箱：\(error.localizedDescription)"
        }
    }

    func handleOpenURL(_ url: URL, modelContext: ModelContext) {
        stageAndImportFile(url, kind: .openURL, modelContext: modelContext)
    }

    func cancel() {
        guard isRunning else { return }
        isCancelling = true
        task?.cancel()
    }

    func clearResult() {
        guard !isRunning else { return }
        phase = .idle
        progress = nil
        summary = nil
        lastResult = nil
        issueMessages = []
        lastErrorMessage = nil
    }

    private func startPreparedFolderImport(
        _ url: URL,
        kind: RunKind,
        source: MediaSource,
        collectionName: String,
        modelContext: ModelContext
    ) {
        guard !isRunning else { return }
        beginRun(kind: kind)
        task = Task { [weak self] in
            await self?.runFolder(
                rootURL: url,
                kind: kind,
                source: source,
                collectionName: collectionName,
                removeSourceAfterSuccess: false,
                modelContext: modelContext
            )
        }
    }

    private func startInboxImport(
        _ urls: [URL],
        kind: RunKind,
        modelContext: ModelContext
    ) {
        guard !isRunning, !urls.isEmpty else { return }
        beginRun(kind: kind)
        task = Task { [weak self] in
            await self?.runInbox(urls, kind: kind, modelContext: modelContext)
        }
    }

    private func beginRun(kind: RunKind) {
        isRunning = true
        isCancelling = false
        phase = .scanning
        progress = nil
        summary = nil
        lastResult = nil
        issueMessages = []
        lastErrorMessage = nil
        currentKind = kind
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
    }

    private func runFolder(
        rootURL: URL,
        kind: RunKind,
        source: MediaSource,
        collectionName: String,
        removeSourceAfterSuccess: Bool,
        modelContext: ModelContext
    ) async {
        let didStart = rootURL.startAccessingSecurityScopedResource()
        defer {
            if didStart { rootURL.stopAccessingSecurityScopedResource() }
        }

        do {
            let startedAt = Date()
            let result = try await importService.importFolder(
                rootURL: rootURL,
                source: source,
                rootName: collectionName,
                collectionName: collectionName,
                in: modelContext,
                options: importOptions(),
                progress: { [weak self] update in
                    Task { @MainActor [weak self] in
                        self?.apply(update)
                    }
                }
            )
            let report = result.report
            let summary = makeSummary(
                kind: kind,
                collectionName: collectionName,
                report: report,
                duration: Date().timeIntervalSince(startedAt),
                reportPath: result.reportPath
            )
            lastResult = result
            finish(
                phase: report.cancelled ? .cancelled : .finished,
                summary: summary,
                issues: report.allIssues.map { "\($0.kind.displayName)：\($0.relativePath) — \($0.message)" }
            )

            if removeSourceAfterSuccess,
               !report.cancelled,
               report.failedCount == 0,
               report.unsupportedCount == 0 {
                try? inbox.remove(rootURL)
            }
            refreshInboxPendingCount()
        } catch is CancellationError {
            finish(phase: .cancelled, summary: nil, issues: [])
        } catch {
            finishWithError(error)
        }
    }

    private func runInbox(
        _ urls: [URL],
        kind: RunKind,
        modelContext: ModelContext
    ) async {
        let startedAt = Date()
        let collectionName = kind == .inbox ? "收件箱" : "外部打开"
        let source: MediaSource = kind == .inbox ? .finder : .openIn
        var importedCount = 0
        var relinkedCount = 0
        var duplicateCount = 0
        var unsupportedCount = 0
        var failedCount = 0
        var copiedBytes: Int64 = 0
        var totalCandidates = 0
        var supportedFiles = 0
        var messages: [String] = []
        var cancelled = false
        var lastReportPath: String?

        for url in urls {
            if Task.isCancelled {
                cancelled = true
                break
            }
            do {
                let result = try await importService.importFolder(
                    rootURL: url,
                    source: source,
                    rootName: url.lastPathComponent,
                    collectionName: collectionName,
                    in: modelContext,
                    options: importOptions(),
                    progress: { [weak self] update in
                        Task { @MainActor [weak self] in
                            self?.apply(update)
                        }
                    }
                )
                let report = result.report
                lastResult = result
                lastReportPath = result.reportPath
                importedCount += report.importedCount
                relinkedCount += report.relinkedCount
                duplicateCount += report.duplicateCount
                unsupportedCount += report.unsupportedCount
                failedCount += report.failedCount
                copiedBytes += report.copiedBytes
                totalCandidates += report.totalCandidates
                supportedFiles += report.supportedFiles
                messages.append(contentsOf: report.allIssues.map {
                    "\($0.kind.displayName)：\($0.relativePath) — \($0.message)"
                })
                if report.cancelled {
                    cancelled = true
                    break
                }
                if report.failedCount == 0, report.unsupportedCount == 0 {
                    try? inbox.remove(url)
                }
            } catch is CancellationError {
                cancelled = true
                break
            } catch {
                failedCount += 1
                messages.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        refreshInboxPendingCount()
        let summary = RunSummary(
            kind: kind,
            collectionName: collectionName,
            totalCandidates: totalCandidates,
            supportedFiles: supportedFiles,
            importedCount: importedCount,
            relinkedCount: relinkedCount,
            duplicateCount: duplicateCount,
            unsupportedCount: unsupportedCount,
            failedCount: failedCount,
            copiedBytes: copiedBytes,
            duration: Date().timeIntervalSince(startedAt),
            cancelled: cancelled,
            messages: messages,
            reportPath: lastReportPath
        )
        finish(phase: cancelled ? .cancelled : .finished, summary: summary, issues: messages)
    }

    private func makeSummary(
        kind: RunKind,
        collectionName: String,
        report: ImportRunResult,
        duration: TimeInterval,
        reportPath: String?
    ) -> RunSummary {
        RunSummary(
            kind: kind,
            collectionName: collectionName,
            totalCandidates: report.totalCandidates,
            supportedFiles: report.supportedFiles,
            importedCount: report.importedCount,
            relinkedCount: report.relinkedCount,
            duplicateCount: report.duplicateCount,
            unsupportedCount: report.unsupportedCount,
            failedCount: report.failedCount,
            copiedBytes: report.copiedBytes,
            duration: duration,
            cancelled: report.cancelled,
            messages: report.allIssues.map {
                "\($0.kind.displayName)：\($0.relativePath) — \($0.message)"
            },
            reportPath: reportPath
        )
    }

    private func importOptions() -> ImportEngine.Options {
        var options = ImportEngine.Options()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--m1-slow-copy") {
            options.chunkDelay = .milliseconds(30)
            options.chunkSize = 64 * 1024
        }
        #endif
        return options
    }

    private func apply(_ update: ImportProgress) {
        progress = update
        phase = update.phase
    }

    private func finish(
        phase: ImportPhase,
        summary: RunSummary?,
        issues: [String]
    ) {
        self.phase = phase
        self.summary = summary
        self.issueMessages = issues
        self.isRunning = false
        self.isCancelling = false
        self.currentKind = nil
        self.task = nil
        self.refreshInboxPendingCount()
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }

    private func finishWithError(_ error: Error) {
        phase = .failed
        lastErrorMessage = error.localizedDescription
        summary = nil
        issueMessages = [error.localizedDescription]
        isRunning = false
        isCancelling = false
        currentKind = nil
        task = nil
        refreshInboxPendingCount()
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }
}
