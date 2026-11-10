import Foundation
import Observation
import SwiftData
import LocalPodKit

@MainActor
@Observable
final class ImportCoordinator {
    enum RunKind: String, Sendable {
        case folder = "文件夹"
        case demo = "演示文件夹"
        case inbox = "收件箱"
        case openURL = "外部打开"

        var displayName: String { rawValue }
    }

    struct RunSummary: Sendable {
        var kind: RunKind
        var importedCount: Int
        var failedCount: Int
        var skippedUnsupportedCount: Int
        var copiedBytes: Int64
        var duration: TimeInterval
        var cancelled: Bool
        var messages: [String]
    }

    private(set) var phase: ImportPhase = .idle
    private(set) var progress: ImportProgress?
    private(set) var summary: RunSummary?
    private(set) var issueMessages: [String] = []
    private(set) var isRunning = false
    private(set) var isCancelling = false
    private(set) var currentKind: RunKind?
    private(set) var lastErrorMessage: String?
    private(set) var inboxPendingCount = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private let engine = ImportEngine()
    @ObservationIgnored private let storage = MediaStorage.live
    @ObservationIgnored private let inbox = ImportInbox.live

    func bootstrap(modelContext: ModelContext) {
        do {
            try inbox.ensureExists()
            refreshInboxPendingCount()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        guard !didBootstrap else { return }
        didBootstrap = true
        importInboxIfNeeded(modelContext: modelContext)
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
        beginRun(kind: .folder)
        task = Task { [weak self] in
            await self?.runImport(
                rootURL: url,
                kind: .folder,
                folderName: url.lastPathComponent,
                removeSourceAfterSuccess: false,
                modelContext: modelContext
            )
        }
    }

    func importDemoFolder(modelContext: ModelContext) {
        guard !isRunning else { return }
        guard let template = Bundle.main.url(forResource: "demo-audio", withExtension: "m4a") else {
            phase = .failed
            lastErrorMessage = "找不到内置演示音频 demo-audio.m4a。"
            return
        }
        let demoRoot = storage.applicationSupportRoot
            .appendingPathComponent("DemoInput", isDirectory: true)
        beginRun(kind: .demo)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let root = try await Task.detached(priority: .userInitiated) {
                    try DemoFolderFactory.makeIfNeeded(
                        at: demoRoot,
                        audioTemplateURL: template
                    )
                }.value
                await self.runImport(
                    rootURL: root,
                    kind: .demo,
                    folderName: "演示文件夹",
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
        issueMessages = []
        lastErrorMessage = nil
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
        issueMessages = []
        lastErrorMessage = nil
        currentKind = kind
    }

    private func runImport(
        rootURL: URL,
        kind: RunKind,
        folderName: String,
        removeSourceAfterSuccess: Bool,
        modelContext: ModelContext
    ) async {
        do {
            let session = try storage.newSessionURL()
            let performed = try await performImport(
                rootURL: rootURL,
                destinationRootURL: session,
                folderName: folderName,
                removeSourceAfterSuccess: removeSourceAfterSuccess,
                modelContext: modelContext
            )
            let summary = RunSummary(
                kind: kind,
                importedCount: performed.insertedCount,
                failedCount: performed.messages.count,
                skippedUnsupportedCount: performed.result.skippedUnsupportedCount,
                copiedBytes: performed.result.copiedBytes,
                duration: performed.result.finishedAt.timeIntervalSince(performed.result.startedAt),
                cancelled: performed.result.cancelled,
                messages: performed.messages
            )
            finish(
                phase: performed.result.cancelled ? .cancelled : .finished,
                summary: summary
            )
        } catch is CancellationError {
            finish(phase: .cancelled, summary: nil)
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
        var importedCount = 0
        var skippedUnsupportedCount = 0
        var copiedBytes: Int64 = 0
        var messages: [String] = []
        var cancelled = false

        for url in urls {
            if Task.isCancelled {
                cancelled = true
                break
            }
            do {
                let session = try storage.newSessionURL()
                let performed = try await performImport(
                    rootURL: url,
                    destinationRootURL: session,
                    folderName: kind == .inbox ? "收件箱" : "外部打开",
                    removeSourceAfterSuccess: true,
                    modelContext: modelContext
                )
                importedCount += performed.insertedCount
                skippedUnsupportedCount += performed.result.skippedUnsupportedCount
                copiedBytes += performed.result.copiedBytes
                messages.append(contentsOf: performed.messages)
                if performed.result.cancelled {
                    cancelled = true
                    break
                }
            } catch is CancellationError {
                cancelled = true
                break
            } catch {
                messages.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        refreshInboxPendingCount()
        let summary = RunSummary(
            kind: kind,
            importedCount: importedCount,
            failedCount: messages.count,
            skippedUnsupportedCount: skippedUnsupportedCount,
            copiedBytes: copiedBytes,
            duration: Date().timeIntervalSince(startedAt),
            cancelled: cancelled,
            messages: messages
        )
        finish(phase: cancelled ? .cancelled : .finished, summary: summary)
    }

    private struct PerformedImport {
        var result: ImportRunResult
        var insertedCount: Int
        var messages: [String]
    }

    private func performImport(
        rootURL: URL,
        destinationRootURL: URL,
        folderName: String,
        removeSourceAfterSuccess: Bool,
        modelContext: ModelContext
    ) async throws -> PerformedImport {
        let didStart = rootURL.startAccessingSecurityScopedResource()
        defer {
            if didStart { rootURL.stopAccessingSecurityScopedResource() }
        }

        let result = try await engine.scanAndImport(
            rootURL: rootURL,
            destinationRootURL: destinationRootURL,
            progress: { [weak self] update in
                Task { @MainActor [weak self] in
                    self?.apply(update)
                }
            }
        )

        var messages = result.issues.map { "\($0.relativePath)：\($0.message)" }
        var insertedCount = 0
        for imported in result.importedFiles {
            do {
                let relativePath = try storage.relativePath(for: imported.destinationURL)
                let item = MediaItem(
                    title: imported.displayName,
                    relativePath: relativePath,
                    kind: imported.kind,
                    fileExtension: imported.destinationURL.pathExtension,
                    byteSize: imported.byteSize,
                    folderName: folderName,
                    source: .imported
                )
                modelContext.insert(item)
                insertedCount += 1
            } catch {
                messages.append("\(imported.sourceRelativePath)：\(error.localizedDescription)")
            }
        }

        if insertedCount > 0 {
            do {
                try modelContext.save()
            } catch {
                messages.append("保存数据库失败：\(error.localizedDescription)")
                throw error
            }
        }

        if removeSourceAfterSuccess,
           result.issues.isEmpty,
           result.skippedUnsupportedCount == 0,
           !result.cancelled {
            try? inbox.remove(rootURL)
        }

        if result.importedFiles.isEmpty {
            try? FileManager.default.removeItem(at: destinationRootURL)
        }

        return PerformedImport(
            result: result,
            insertedCount: insertedCount,
            messages: messages
        )
    }

    private func apply(_ update: ImportProgress) {
        progress = update
        phase = update.phase
    }

    private func finish(phase: ImportPhase, summary: RunSummary?) {
        self.phase = phase
        self.summary = summary
        self.issueMessages = summary?.messages ?? []
        self.isRunning = false
        self.isCancelling = false
        self.currentKind = nil
        self.task = nil
        refreshInboxPendingCount()
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
    }
}
