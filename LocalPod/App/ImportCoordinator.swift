import Foundation
import Observation
import SwiftData
import LocalPodKit
#if os(iOS)
import UIKit
#endif

/// A snapshot of `Documents/Import` produced off the main actor.
private struct InboxObservation: Sendable {
    var pendingURLs: [URL]
    var stableURLs: [URL]
    var unstableCount: Int
    var skippedCount: Int
    var unsupportedStableURLs: [URL]
    var performedStabilityCheck: Bool
    var failureMessage: String?
}

private struct InboxRunItem: Sendable {
    let url: URL
    let source: MediaSource
}

private struct InboxURLReport: Codable, Sendable {
    let fileName: String
    let source: String
    let reportPath: String?
    let importedCount: Int
    let relinkedCount: Int
    let duplicateCount: Int
    let unsupportedCount: Int
    let failedCount: Int
    let errorMessage: String?
}

private struct InboxRunReport: Codable, Sendable {
    let runID: UUID
    let kind: String
    let collectionName: String
    let startedAt: Date
    let finishedAt: Date
    let durationSeconds: Double
    let totalCandidates: Int
    let supportedFiles: Int
    let importedCount: Int
    let relinkedCount: Int
    let duplicateCount: Int
    let unsupportedCount: Int
    let failedCount: Int
    let copiedBytes: Int64
    let cancelled: Bool
    let reportPaths: [String]
    let items: [InboxURLReport]
}

@MainActor
@Observable
final class ImportCoordinator {
    enum RunKind: String, Sendable {
        case folder = "文件夹"
        case demo = "演示文件夹"
        case acceptance = "验收文件夹"
        case inbox = "收件箱"
        case openURL = "外部打开"
        case sample = "示例内容"
        case wifi = "Wi-Fi 上传"
        case linkedFolder = "链接文件夹"

        var displayName: String {
            switch self {
            case .folder: L10n.string("import.run.folder")
            case .demo: L10n.string("import.run.demo")
            case .acceptance: L10n.string("import.run.acceptance")
            case .inbox: L10n.string("import.run.inbox")
            case .openURL: L10n.string("import.run.openURL")
            case .sample: L10n.string("import.run.sample")
            case .wifi: L10n.string("import.run.wifi")
            case .linkedFolder: L10n.string("import.run.linkedFolder")
            }
        }
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
    private(set) var inboxUnstableCount = 0
    private(set) var inboxSkippedCount = 0
    private(set) var inboxHasPendingFailures = false
    private(set) var isInboxAutoRetrySuspended = false
    private(set) var lastCleanupSummary: LibraryCleanupSummary?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private let storage = MediaStorage.live
    @ObservationIgnored private let inbox = ImportInbox.live
    @ObservationIgnored private let stability = ImportInboxStability()
    @ObservationIgnored private let libraryService = LibraryService(storage: .live)
    @ObservationIgnored private lazy var importService = FolderImportService(
        storage: storage,
        library: libraryService
    )

    /// Inbox scans are asynchronous; this flag prevents overlapping snapshots.
    @ObservationIgnored private var isObservingInbox = false
    /// Visible top-level paths seen by the previous inbox observation.
    @ObservationIgnored private var knownInboxPaths: Set<String> = []
    /// Open-in and picker items are copied atomically into the inbox, so they do
    /// not need the size-stability gate. This remembers their intended source.
    @ObservationIgnored private var stagedSourcesByPath: [String: MediaSource] = [:]
    /// Items staged while another run was active; consumed when that run ends.
    @ObservationIgnored private var queuedStagedItems: [InboxRunItem] = []
    /// Paths that failed in the run which suspended auto-retry. They stay out
    /// of automatic runs until the user asks for a retry or a newly appeared
    /// item has been processed, so a repeatedly failing item cannot starve a
    /// fresh drop.
    @ObservationIgnored private var pausedFailurePaths: Set<String> = []
    /// Completed browser batches that arrived while another import was
    /// running. They are staged safely on disk and consumed in order.
    @ObservationIgnored private var queuedWiFiImports: [WiFiCompletedUpload] = []

    /// Delivery hook for the local "import finished/failed" notification. The
    /// default schedules the real `UNNotificationRequest`; the coordinator
    /// still owns the pure policy decision so all run exit points share it.
    @ObservationIgnored var deliverImportNotification: ((ImportNotificationDecision) -> Void)? = {
        decision in
        Task { @MainActor in
            await ImportNotifier.notify(decision: decision)
        }
    }

    func bootstrap(modelContext: ModelContext) {
        do {
            try inbox.ensureExists()
            _ = try inbox.cleanupStaleStaging()
            refreshInboxPendingCount()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        guard !didBootstrap else { return }
        didBootstrap = true
        runMaintenance(modelContext: modelContext)
        recoverWiFiUploads(modelContext: modelContext)
        importInboxIfNeeded(modelContext: modelContext)
    }

    func runMaintenance(modelContext: ModelContext) {
        guard !isRunning else { return }
        do {
            let summary = try libraryService.reconcile(in: modelContext)
            lastCleanupSummary = lastCleanupSummary.map { $0.merging(summary) } ?? summary
        } catch {
            lastErrorMessage = L10n.format(
                "error.import.cleanupFailed",
                error.localizedDescription
            )
        }
    }

    func refreshInboxPendingCount() {
        inboxPendingCount = (try? inbox.pendingURLs().count) ?? 0
        inboxSkippedCount = Self.skippedCount(inbox: inbox)
    }

    /// Foreground/launch scan. Respects the retry suspension so a failing item
    /// cannot loop every two seconds.
    func importInboxIfNeeded(modelContext: ModelContext) {
        refreshInboxPendingCount()
        requestInboxScan(modelContext: modelContext)
    }

    /// Explicit user action: clears a suspended auto-retry and scans now.
    func scanInboxNow(modelContext: ModelContext) {
        isInboxAutoRetrySuspended = false
        inboxHasPendingFailures = false
        pausedFailurePaths.removeAll()
        importInboxIfNeeded(modelContext: modelContext)
    }

    /// Explicit "重试失败" action for inbox/open-in failures.
    func retryInboxFailures(modelContext: ModelContext) {
        scanInboxNow(modelContext: modelContext)
    }

    /// Folder imports are in-place links: the picker URL is bookmarked and the
    /// files stay where they are. Nothing is copied into the sandbox, so the
    /// folder also appears under Settings → linked folders and can be rescanned
    /// later.
    func startFolderImport(_ url: URL, modelContext: ModelContext) {
        guard !isRunning else { return }
        linkFolder(url, modelContext: modelContext)
    }

    // MARK: - Linked folders (链接文件夹 + 增量重扫)

    /// Identifies the row a sync run is recording into, so the completion
    /// handler can find the LinkedFolder even if SwiftData's context state
    /// moved on during the import.
    private struct PendingLinkedFolderSync {
        let folderID: UUID
        let rootName: String
    }

    /// Runs whose completion must update a LinkedFolder row. Keyed by the
    /// linked folder's id; at most one runs at a time (guarded by isRunning).
    @ObservationIgnored private var pendingLinkedFolderSync: PendingLinkedFolderSync?

    /// Links a picked folder and immediately runs the first sync. The first
    /// sync reuses the normal folder-import pipeline, so SHA-256 dedup makes
    /// it a no-op for files already imported from the same content, and the
    /// full pipeline (progress UI, report, ImportSession row) applies.
    ///
    /// The security scope from the document picker is only needed long enough
    /// to create the bookmark; later syncs regain access by resolving it.
    func linkFolder(
        _ url: URL,
        modelContext: ModelContext
    ) {
        guard !isRunning else { return }
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        do {
            // Re-picking an already linked folder resyncs that row instead of
            // creating a second bookmark for the same source.
            let existing = (try? modelContext.fetch(FetchDescriptor<LinkedFolder>())) ?? []
            for folder in existing {
                guard case .success(let access) = LinkedFolderStore.resolve(folder.bookmarkData) else {
                    continue
                }
                let matches = access.url.standardizedFileURL == url.standardizedFileURL
                if matches {
                    if let refreshed = access.refreshedBookmark {
                        folder.bookmarkData = refreshed
                    }
                    folder.isStale = false
                    try? modelContext.save()
                    access.stop()
                    beginLinkedFolderSync(
                        folder,
                        resolvedURL: url,
                        modelContext: modelContext
                    )
                    return
                }
                access.stop()
            }

            let bookmark = try LinkedFolderStore.makeBookmark(for: url)
            let folder = LinkedFolder(
                bookmarkData: bookmark,
                rootName: url.lastPathComponent
            )
            modelContext.insert(folder)
            try modelContext.save()
            beginLinkedFolderSync(folder, resolvedURL: url, modelContext: modelContext)
        } catch {
            phase = .failed
            lastErrorMessage = L10n.format(
                "error.linkedFolder.linkFailed",
                error.localizedDescription
            )
        }
    }

    /// Re-scans a linked folder. Resolves the bookmark first; a stale link is
    /// flagged on the row (local copies are never touched) and reported. The
    /// scan is incremental only for bookkeeping — the import itself still runs
    /// the standard pipeline, where unchanged files skip as fingerprint
    /// duplicates and only new files are copied. Files removed from the source
    /// are reported in `lastRemovedCount` but their local copies are retained
    /// (the user copied them intentionally; deletion stays a manual decision).
    func rescanLinkedFolder(_ folder: LinkedFolder, modelContext: ModelContext) {
        guard !isRunning else { return }
        guard folder.enabled else { return }
        switch LinkedFolderStore.resolve(folder.bookmarkData) {
        case .failure(let error):
            LinkedFolderStore.markStale(folder)
            try? modelContext.save()
            phase = .failed
            lastErrorMessage = error.localizedDescription
        case .success(let access):
            access.withAccess { resolvedURL in
                // A stale bookmark that still resolved was re-created while
                // the scope was live; persist it so the next launch is clean.
                if let refreshed = access.refreshedBookmark {
                    folder.bookmarkData = refreshed
                    folder.isStale = false
                    try? modelContext.save()
                }
                beginLinkedFolderSync(folder, resolvedURL: resolvedURL, modelContext: modelContext)
            }
        }
    }

    /// Replaces the bookmark after the user re-picked the folder and clears
    /// the stale flag. Local media is untouched.
    func relinkFolder(_ folder: LinkedFolder, newURL: URL, modelContext: ModelContext) {
        let didStart = newURL.startAccessingSecurityScopedResource()
        defer {
            if didStart { newURL.stopAccessingSecurityScopedResource() }
        }
        do {
            let bookmark = try LinkedFolderStore.makeBookmark(for: newURL)
            LinkedFolderStore.relink(folder, bookmarkData: bookmark)
            try modelContext.save()
            // Re-authorizing is also the moment to pick up anything that
            // changed while the link was broken.
            beginLinkedFolderSync(folder, resolvedURL: newURL, modelContext: modelContext)
        } catch {
            phase = .failed
            lastErrorMessage = L10n.format(
                "error.linkedFolder.linkFailed",
                error.localizedDescription
            )
        }
    }

    /// Removes only the link row; imported media and collections stay.
    func removeLinkedFolder(_ folder: LinkedFolder, modelContext: ModelContext) {
        modelContext.delete(folder)
        try? modelContext.save()
    }

    /// Shared tail of `linkFolder`/`rescanLinkedFolder`: start one folder
    /// import through the standard run path, remembering which row to update
    /// when it finishes.
    private func beginLinkedFolderSync(
        _ folder: LinkedFolder,
        resolvedURL: URL,
        modelContext: ModelContext
    ) {
        guard !isRunning else { return }
        pendingLinkedFolderSync = PendingLinkedFolderSync(
            folderID: folder.id,
            rootName: folder.rootName
        )
        beginRun(kind: .linkedFolder)
        task = Task { [weak self] in
            await self?.runLinkedFolderSync(
                resolvedURL: resolvedURL,
                rootName: folder.rootName,
                modelContext: modelContext
            )
            self?.pendingLinkedFolderSync = nil
        }
    }

    /// One rescan = full folder import (dedup skips unchanged files) + diff
    /// bookkeeping. Removal detection compares source-side keys so sandbox
    /// copy paths never leak into the comparison.
    private func runLinkedFolderSync(
        resolvedURL: URL,
        rootName: String,
        modelContext: ModelContext
    ) async {
        let didStart = resolvedURL.startAccessingSecurityScopedResource()
        defer {
            if didStart { resolvedURL.stopAccessingSecurityScopedResource() }
        }

        // Snapshot the pre-sync state before the import mutates the library.
        let folderID = pendingLinkedFolderSync?.folderID
        let existingKeys: Set<String>
        if let folderID {
            existingKeys = (try? LinkedFolderStore.existingSourceKeys(
                forLinkedFolderID: folderID,
                in: modelContext
            )) ?? []
        } else {
            existingKeys = (try? LinkedFolderStore.existingSourceKeys(
                forLinkedFolderNamed: rootName,
                in: modelContext
            )) ?? []
        }
        guard let folderID else {
            finishWithError(
                LinkedFolderError.staleBookmark,
                modelContext: modelContext
            )
            return
        }

        do {
            let startedAt = Date()
            let result = try await importService.importLinkedFolder(
                rootURL: resolvedURL,
                source: .files,
                rootName: rootName,
                linkedFolderID: folderID,
                collectionName: rootName,
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
                kind: .linkedFolder,
                collectionName: rootName,
                report: report,
                duration: Date().timeIntervalSince(startedAt),
                reportPath: result.reportPath
            )
            lastResult = result
            let issues = report.allIssues.map {
                L10n.format(
                    "import.issue.line",
                    $0.kind.displayName,
                    $0.relativePath,
                    $0.message
                )
            }

            recordLinkedFolderResult(
                folderID: folderID,
                report: report,
                existingKeys: existingKeys,
                scannedRootURL: resolvedURL,
                modelContext: modelContext
            )

            finish(
                phase: report.cancelled ? .cancelled : .finished,
                summary: summary,
                issues: issues,
                modelContext: modelContext
            )
        } catch {
            finishWithError(error, modelContext: modelContext)
        }
    }

    /// Updates the LinkedFolder row after a sync: scanned-at, imported count,
    /// removed count, and staleness. Bookkeeping must never fail the run.
    private func recordLinkedFolderResult(
        folderID: UUID?,
        report: ImportRunResult,
        existingKeys: Set<String>,
        scannedRootURL: URL,
        modelContext: ModelContext
    ) {
        guard let folderID else { return }
        var descriptor = FetchDescriptor<LinkedFolder>(
            predicate: #Predicate { $0.id == folderID }
        )
        descriptor.fetchLimit = 1
        guard let folder = try? modelContext.fetch(descriptor).first else { return }
        guard !report.cancelled else {
            // A cancelled sync did not see the full folder; leave the old
            // bookkeeping untouched.
            return
        }

        if let scan = try? FolderScanner().scan(
            rootURL: scannedRootURL,
            limits: FolderScanner.Limits()
        ) {
            // Unchanged files never enter the import report, so removal and
            // imported counts come from a fresh diff against the source.
            let diff = LinkedFolderStore.diff(
                existingSourceKeys: existingKeys,
                scannedFiles: scan.files
            )
            LinkedFolderStore.recordScan(
                folder,
                importedCount: diff.newFiles.count,
                removedCount: diff.removedPaths.count
            )
        } else if report.importedCount > 0 || report.relinkedCount > 0 {
            // Fresh-scan fallback: the import report is the best available
            // count when the source cannot be re-enumerated.
            LinkedFolderStore.recordScan(
                folder,
                importedCount: report.importedCount,
                removedCount: 0
            )
        }
        try? modelContext.save()
    }


    func importDemoFolder(modelContext: ModelContext) {
        importBuiltInFolder(
            kind: .demo,
            collectionName: L10n.string("collection.demo"),
            acceptance: false,
            modelContext: modelContext
        )
    }

    func importAcceptanceFolder(modelContext: ModelContext) {
        importBuiltInFolder(
            kind: .acceptance,
            collectionName: L10n.string("collection.acceptance"),
            acceptance: true,
            modelContext: modelContext
        )
    }

    /// User-facing built-in sample set. The files live in a folder reference
    /// inside the app bundle, so the existing import pipeline can scan them
    /// without touching security-scoped URLs or anything outside the sandbox.
    static let sampleCollectionName = "示例内容"

    static var sampleRootURL: URL? {
        guard let url = Bundle.main.url(
            forResource: "SampleContent",
            withExtension: nil
        ) else {
            return nil
        }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return isDirectory ? url : nil
    }

    var isSampleImportAvailable: Bool {
        Self.sampleRootURL != nil
    }

    func importSampleContent(modelContext: ModelContext) {
        guard !isRunning else { return }
        guard let root = Self.sampleRootURL else {
            phase = .failed
            lastErrorMessage = L10n.string("error.import.sampleMissing")
            return
        }
        beginRun(kind: .sample)
        task = Task { [weak self] in
            await self?.runFolder(
                rootURL: root,
                kind: .sample,
                source: .sample,
                collectionName: Self.sampleCollectionName,
                removeSourceAfterSuccess: false,
                modelContext: modelContext
            )
        }
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
            lastErrorMessage = L10n.string("error.import.demoMissing")
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
                self.finishWithError(error, modelContext: modelContext)
            }
        }
    }

    /// Stages an open-in/picker item and runs it immediately, or queues it when
    /// another import is already active. Staging itself is atomic, so queued
    /// items never expose a partially copied file to the inbox scanner.
    func stageAndImportFile(_ url: URL, kind: RunKind = .openURL, modelContext: ModelContext) {
        guard url.isFileURL else { return }
        let source: MediaSource = kind == .inbox ? .finder : .openIn
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let staged = try inbox.stage(url: url)
            stagedSourcesByPath[staged.standardizedFileURL.path] = source
            refreshInboxPendingCount()
            if isRunning {
                queuedStagedItems.append(InboxRunItem(url: staged, source: source))
                return
            }
            // A new external item is a user signal to leave a suspended state.
            isInboxAutoRetrySuspended = false
            inboxHasPendingFailures = false
            startInboxImport(
                [InboxRunItem(url: staged, source: source)],
                kind: kind == .inbox ? .inbox : .openURL,
                modelContext: modelContext
            )
        } catch {
            phase = .failed
            lastErrorMessage = L10n.format(
                "error.import.stageFailed",
                error.localizedDescription
            )
        }
    }

    func handleOpenURL(_ url: URL, modelContext: ModelContext) {
        stageAndImportFile(url, kind: .openURL, modelContext: modelContext)
    }

    /// Consumes a completed browser upload. If another run is active the
    /// completed staging directory stays on disk and is imported once the
    /// current run finishes.
    func importWiFiSession(
        _ completed: WiFiCompletedUpload,
        modelContext: ModelContext
    ) {
        if isRunning {
            if !queuedWiFiImports.contains(where: { $0.sessionID == completed.sessionID }) {
                queuedWiFiImports.append(completed)
            }
            return
        }
        startWiFiImport(completed, modelContext: modelContext)
    }

    private func startWiFiImport(
        _ completed: WiFiCompletedUpload,
        modelContext: ModelContext
    ) {
        guard !isRunning else {
            if !queuedWiFiImports.contains(where: { $0.sessionID == completed.sessionID }) {
                queuedWiFiImports.append(completed)
            }
            return
        }
        let collectionName = completed.suggestedCollectionName
            ?? L10n.string("collection.wifi")
        beginRun(kind: .wifi)
        task = Task { [weak self] in
            await self?.runFolder(
                rootURL: completed.directoryURL,
                kind: .wifi,
                source: .wifi,
                collectionName: collectionName,
                removeSourceAfterSuccess: false,
                wifiSessionID: completed.sessionID,
                modelContext: modelContext
            )
        }
    }

    private func recoverWiFiUploads(modelContext: ModelContext) {
        do {
            try WiFiUploadStorage.store.cleanupIncompleteSessions()
            for completed in try WiFiUploadStorage.store.pendingCompletedSessions() {
                importWiFiSession(completed, modelContext: modelContext)
            }
        } catch {
            lastErrorMessage = L10n.format(
                "error.wifi.recoveryFailed",
                error.localizedDescription
            )
        }
    }

    private func startNextQueuedWiFiImportIfNeeded(modelContext: ModelContext) {
        guard !isRunning, !queuedWiFiImports.isEmpty else { return }
        let next = queuedWiFiImports.removeFirst()
        startWiFiImport(next, modelContext: modelContext)
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
        _ items: [InboxRunItem],
        kind: RunKind,
        modelContext: ModelContext
    ) {
        guard !isRunning, !items.isEmpty else { return }
        beginRun(kind: kind)
        task = Task { [weak self] in
            await self?.runInbox(items, kind: kind, modelContext: modelContext)
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
        wifiSessionID: UUID? = nil,
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
            var issues = report.allIssues.map {
                L10n.format(
                    "import.issue.line",
                    $0.kind.displayName,
                    $0.relativePath,
                    $0.message
                )
            }
            // Browser uploads are copies of the user's computer files. Remove
            // the staging directory after any completed run, including a user
            // cancellation, so a later launch does not silently re-import a
            // batch the user stopped. A thrown error keeps it for recovery.
            if let wifiSessionID {
                do {
                    try WiFiUploadStorage.store.removeSession(wifiSessionID)
                } catch {
                    issues.append(L10n.format(
                        "error.wifi.cleanupFailed",
                        error.localizedDescription
                    ))
                }
            }
            finish(
                phase: report.cancelled ? .cancelled : .finished,
                summary: summary,
                issues: issues,
                modelContext: modelContext
            )

            if removeSourceAfterSuccess,
               !report.cancelled,
               report.failedCount == 0,
               report.unsupportedCount == 0 {
                try? inbox.remove(rootURL)
            }
            refreshInboxPendingCount()
        } catch is CancellationError {
            finish(phase: .cancelled, summary: nil, issues: [], modelContext: modelContext)
        } catch {
            finishWithError(error, modelContext: modelContext)
        }
    }

    /// Imports every stable inbox item plus queued open-in items in one run and
    /// produces one aggregated summary/report.
    private func runInbox(
        _ items: [InboxRunItem],
        kind: RunKind,
        modelContext: ModelContext
    ) async {
        let startedAt = Date()
        let collectionName = kind == .openURL
            ? L10n.string("collection.openIn")
            : L10n.string("collection.inbox")
        var importedCount = 0
        var relinkedCount = 0
        var duplicateCount = 0
        var unsupportedCount = 0
        var failedCount = 0
        var copiedBytes: Int64 = 0
        var totalCandidates = 0
        var supportedFiles = 0
        var messages: [String] = []
        var urlReports: [InboxURLReport] = []
        var cancelled = false
        var hasPendingFailure = false
        var failedPaths: Set<String> = []

        for item in items {
            if Task.isCancelled {
                cancelled = true
                break
            }
            do {
                let result = try await importService.importFolder(
                    rootURL: item.url,
                    source: item.source,
                    rootName: item.url.lastPathComponent,
                    collectionName: item.source == .openIn
                        ? L10n.string("collection.openIn")
                        : L10n.string("collection.inbox"),
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
                importedCount += report.importedCount
                relinkedCount += report.relinkedCount
                duplicateCount += report.duplicateCount
                unsupportedCount += report.unsupportedCount
                failedCount += report.failedCount
                copiedBytes += report.copiedBytes
                totalCandidates += report.totalCandidates
                supportedFiles += report.supportedFiles
                messages.append(contentsOf: report.allIssues.map {
                    L10n.format(
                        "import.issue.line",
                        $0.kind.displayName,
                        $0.relativePath,
                        $0.message
                    )
                })
                urlReports.append(InboxURLReport(
                    fileName: item.url.lastPathComponent,
                    source: item.source.displayName,
                    reportPath: result.reportPath,
                    importedCount: report.importedCount,
                    relinkedCount: report.relinkedCount,
                    duplicateCount: report.duplicateCount,
                    unsupportedCount: report.unsupportedCount,
                    failedCount: report.failedCount,
                    errorMessage: nil
                ))

                if report.cancelled {
                    cancelled = true
                    failedPaths.insert(item.url.standardizedFileURL.path)
                    break
                }
                if report.failedCount == 0, report.unsupportedCount == 0 {
                    do {
                        try inbox.remove(item.url)
                        forgetStagedSource(for: item.url)
                    } catch {
                        hasPendingFailure = true
                        failedPaths.insert(item.url.standardizedFileURL.path)
                        messages.append(L10n.format(
                            "error.inbox.removeFailed",
                            item.url.lastPathComponent,
                            error.localizedDescription
                        ))
                    }
                } else {
                    hasPendingFailure = true
                    failedPaths.insert(item.url.standardizedFileURL.path)
                }
            } catch is CancellationError {
                cancelled = true
                failedPaths.insert(item.url.standardizedFileURL.path)
                break
            } catch {
                failedCount += 1
                hasPendingFailure = true
                failedPaths.insert(item.url.standardizedFileURL.path)
                let message = L10n.format(
                    "error.inbox.fileFailed",
                    item.url.lastPathComponent,
                    error.localizedDescription
                )
                messages.append(message)
                urlReports.append(InboxURLReport(
                    fileName: item.url.lastPathComponent,
                    source: item.source.displayName,
                    reportPath: nil,
                    importedCount: 0,
                    relinkedCount: 0,
                    duplicateCount: 0,
                    unsupportedCount: 0,
                    failedCount: 1,
                    errorMessage: error.localizedDescription
                ))
            }
        }

        refreshInboxPendingCount()
        let hasRemainingItems = inboxPendingCount > 0
        if (hasPendingFailure || cancelled) && hasRemainingItems {
            // Do not loop every poll; a new item or the retry button releases this.
            isInboxAutoRetrySuspended = true
            pausedFailurePaths.formUnion(failedPaths)
        } else if !hasPendingFailure, !cancelled {
            // A clean run clears the previous pause so older failures get one
            // more automatic attempt after the new item has been handled.
            pausedFailurePaths.removeAll()
        }
        inboxHasPendingFailures = hasPendingFailure && hasRemainingItems

        let finishedAt = Date()
        let reportPath = writeRunReport(
            kind: kind,
            collectionName: collectionName,
            startedAt: startedAt,
            finishedAt: finishedAt,
            totalCandidates: totalCandidates,
            supportedFiles: supportedFiles,
            importedCount: importedCount,
            relinkedCount: relinkedCount,
            duplicateCount: duplicateCount,
            unsupportedCount: unsupportedCount,
            failedCount: failedCount,
            copiedBytes: copiedBytes,
            cancelled: cancelled,
            items: urlReports
        )
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
            duration: finishedAt.timeIntervalSince(startedAt),
            cancelled: cancelled,
            messages: messages,
            reportPath: reportPath
        )
        finish(
            phase: cancelled ? .cancelled : .finished,
            summary: summary,
            issues: messages,
            modelContext: modelContext
        )
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
                L10n.format(
                    "import.issue.line",
                    $0.kind.displayName,
                    $0.relativePath,
                    $0.message
                )
            },
            reportPath: reportPath
        )
    }

    private func importOptions() -> ImportEngine.Options {
        var options = ImportEngine.Options()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--m1-slow-copy") {
            // Slow enough that UI tests can observe progress and tap cancel
            // before a small acceptance fixture finishes on fast simulators.
            options.chunkDelay = .milliseconds(150)
            options.chunkSize = 64 * 1024
        }
        #endif
        return options
    }

    private func apply(_ update: ImportProgress) {
        progress = update
        phase = update.phase
    }

    // MARK: - Inbox stability, quarantine, and queued runs

    /// Evaluates the inbox off the main actor. While auto-retry is suspended we
    /// only list top-level items, so a large failing folder is not rescanned on
    /// every poll.
    private func requestInboxScan(modelContext: ModelContext) {
        guard !isRunning, !isObservingInbox else { return }
        isObservingInbox = true
        let inbox = self.inbox
        let stability = self.stability
        let lightweight = isInboxAutoRetrySuspended
        Task { [weak self] in
            let observation = await Task.detached(priority: .utility) {
                Self.observeInbox(inbox: inbox, stability: stability, lightweight: lightweight)
            }.value
            guard let self else { return }
            self.isObservingInbox = false
            if let failure = observation.failureMessage, !self.isRunning {
                self.lastErrorMessage = failure
            } else {
                self.apply(observation, modelContext: modelContext)
            }
        }
    }

    nonisolated private static func observeInbox(
        inbox: ImportInbox,
        stability: ImportInboxStability,
        lightweight: Bool
    ) -> InboxObservation {
        let skipped = skippedCount(inbox: inbox)
        do {
            try inbox.ensureExists()
            let pending = try inbox.pendingURLs()
            guard !lightweight else {
                return InboxObservation(
                    pendingURLs: pending,
                    stableURLs: [],
                    unstableCount: 0,
                    skippedCount: skipped,
                    unsupportedStableURLs: [],
                    performedStabilityCheck: false,
                    failureMessage: nil
                )
            }

            let result = try stability.evaluate(in: inbox.directoryURL)
            var unsupported: [URL] = []
            for url in result.stableURLs {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
                guard values?.isRegularFile == true else { continue }
                if SupportedMedia.kind(for: url) == nil {
                    unsupported.append(url)
                }
            }
            return InboxObservation(
                pendingURLs: pending,
                stableURLs: result.stableURLs,
                unstableCount: result.unstableCount,
                skippedCount: skipped,
                unsupportedStableURLs: unsupported,
                performedStabilityCheck: true,
                failureMessage: nil
            )
        } catch {
            return InboxObservation(
                pendingURLs: [],
                stableURLs: [],
                unstableCount: 0,
                skippedCount: skipped,
                unsupportedStableURLs: [],
                performedStabilityCheck: false,
                failureMessage: L10n.format(
                    "error.inbox.scanFailed",
                    error.localizedDescription
                )
            )
        }
    }

    private func apply(_ observation: InboxObservation, modelContext: ModelContext) {
        guard observation.failureMessage == nil else { return }

        var pending = observation.pendingURLs
        var stable = observation.stableURLs
        inboxPendingCount = pending.count
        inboxSkippedCount = observation.skippedCount
        if observation.performedStabilityCheck {
            inboxUnstableCount = observation.unstableCount
        }

        // Top-level unsupported items must never enter the import pipeline.
        if observation.performedStabilityCheck, !observation.unsupportedStableURLs.isEmpty {
            let quarantined = quarantine(observation.unsupportedStableURLs)
            if !quarantined.isEmpty {
                let movedPaths = Set(quarantined.map { $0.standardizedFileURL.path })
                pending.removeAll { movedPaths.contains($0.standardizedFileURL.path) }
                stable.removeAll { movedPaths.contains($0.standardizedFileURL.path) }
                for url in quarantined {
                    let key = url.standardizedFileURL.path
                    pausedFailurePaths.remove(key)
                    forgetStagedSource(for: url)
                }
                inboxPendingCount = pending.count
                inboxSkippedCount += quarantined.count
            }
        }

        let currentPaths = Set(pending.map { $0.standardizedFileURL.path })
        pausedFailurePaths.formIntersection(currentPaths)
        var discoveredNewItem = false
        if !knownInboxPaths.isEmpty {
            let added = currentPaths.subtracting(knownInboxPaths)
            if !added.isEmpty {
                // A recreated path (same name, different file) is not the old
                // failure; let it through while keeping genuinely old paths out.
                pausedFailurePaths.subtract(added)
                discoveredNewItem = true
                isInboxAutoRetrySuspended = false
            }
        }
        knownInboxPaths = currentPaths

        if pending.isEmpty {
            isInboxAutoRetrySuspended = false
            inboxHasPendingFailures = false
            pausedFailurePaths.removeAll()
            return
        }

        guard observation.performedStabilityCheck else {
            if discoveredNewItem {
                requestInboxScan(modelContext: modelContext)
            }
            return
        }

        guard !isInboxAutoRetrySuspended, !isRunning, !isCancelling else { return }

        var items: [InboxRunItem] = []
        var seen = Set<String>()

        for queued in queuedStagedItems {
            let key = queued.url.standardizedFileURL.path
            guard !pausedFailurePaths.contains(key),
                  currentPaths.contains(key),
                  seen.insert(key).inserted else { continue }
            let source = stagedSourcesByPath[key] ?? queued.source
            items.append(InboxRunItem(url: queued.url, source: source))
        }

        // Staged open-in/picker items are complete copies; retry them without
        // waiting for the stability tracker (e.g. after a relaunch).
        for url in pending {
            let key = url.standardizedFileURL.path
            guard !pausedFailurePaths.contains(key),
                  let source = stagedSourcesByPath[key],
                  seen.insert(key).inserted else { continue }
            items.append(InboxRunItem(url: url, source: source))
        }

        for url in stable {
            let key = url.standardizedFileURL.path
            guard !pausedFailurePaths.contains(key),
                  seen.insert(key).inserted else { continue }
            items.append(InboxRunItem(url: url, source: .finder))
        }

        guard !items.isEmpty else { return }
        queuedStagedItems.removeAll()
        let kind: RunKind = items.contains { $0.source == .finder } ? .inbox : .openURL
        startInboxImport(items, kind: kind, modelContext: modelContext)
    }

    private func quarantine(_ urls: [URL]) -> [URL] {
        guard !urls.isEmpty else { return [] }
        let directory = inbox.directoryURL.appendingPathComponent(".Skipped", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            lastErrorMessage = L10n.format(
                "error.inbox.quarantineDirectory",
                error.localizedDescription
            )
            return []
        }

        var moved: [URL] = []
        for url in urls {
            let destination = Self.uniqueQuarantineDestination(for: url, in: directory)
            do {
                try FileManager.default.moveItem(at: url, to: destination)
                moved.append(url)
            } catch {
                lastErrorMessage = L10n.format(
                    "error.inbox.quarantineFile",
                    url.lastPathComponent
                )
            }
        }
        return moved
    }

    nonisolated private static func uniqueQuarantineDestination(
        for url: URL,
        in directory: URL
    ) -> URL {
        let fileManager = FileManager.default
        let name = PathSanitizer.sanitizeRelativePath(url.lastPathComponent)
        var destination = directory.appendingPathComponent(name)
        let ext = destination.pathExtension
        let stem = destination.deletingPathExtension().lastPathComponent
        var index = 2
        while fileManager.fileExists(atPath: destination.path) {
            let candidate = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            destination = directory.appendingPathComponent(candidate)
            index += 1
        }
        return destination
    }

    nonisolated private static func skippedCount(inbox: ImportInbox) -> Int {
        let directory = inbox.directoryURL.appendingPathComponent(".Skipped", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.count ?? 0
    }

    private func forgetStagedSource(for url: URL) {
        let key = url.standardizedFileURL.path
        stagedSourcesByPath.removeValue(forKey: key)
        queuedStagedItems.removeAll { $0.url.standardizedFileURL.path == key }
        pausedFailurePaths.remove(key)
    }

    /// Writes one aggregated JSON report for the whole inbox/open-in run. It
    /// lists the per-URL report emitted by `FolderImportService`.
    private func writeRunReport(
        kind: RunKind,
        collectionName: String,
        startedAt: Date,
        finishedAt: Date,
        totalCandidates: Int,
        supportedFiles: Int,
        importedCount: Int,
        relinkedCount: Int,
        duplicateCount: Int,
        unsupportedCount: Int,
        failedCount: Int,
        copiedBytes: Int64,
        cancelled: Bool,
        items: [InboxURLReport]
    ) -> String? {
        let directory = storage.applicationSupportRoot
            .appendingPathComponent("ImportReports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let runID = UUID()
            let url = directory.appendingPathComponent(
                "\(formatter.string(from: startedAt))-run-\(runID.uuidString).json"
            )
            let report = InboxRunReport(
                runID: runID,
                kind: kind.rawValue,
                collectionName: collectionName,
                startedAt: startedAt,
                finishedAt: finishedAt,
                durationSeconds: finishedAt.timeIntervalSince(startedAt),
                totalCandidates: totalCandidates,
                supportedFiles: supportedFiles,
                importedCount: importedCount,
                relinkedCount: relinkedCount,
                duplicateCount: duplicateCount,
                unsupportedCount: unsupportedCount,
                failedCount: failedCount,
                copiedBytes: copiedBytes,
                cancelled: cancelled,
                reportPaths: items.compactMap(\.reportPath),
                items: items
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: url, options: .atomic)
            return try? storage.relativePath(for: url)
        } catch {
            return nil
        }
    }

    private func finish(
        phase: ImportPhase,
        summary: RunSummary?,
        issues: [String],
        modelContext: ModelContext
    ) {
        self.phase = phase
        self.summary = summary
        self.issueMessages = issues
        self.isRunning = false
        self.isCancelling = false
        self.currentKind = nil
        self.task = nil
        self.pendingLinkedFolderSync = nil
        self.refreshInboxPendingCount()
        sendImportNotification(phase: phase, summary: summary, errorMessage: nil)
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
        // Process items staged while this run was active, plus any newly stable
        // inbox item (respecting the retry suspension).
        requestInboxScan(modelContext: modelContext)
        startNextQueuedWiFiImportIfNeeded(modelContext: modelContext)
    }

    private func finishWithError(_ error: Error, modelContext: ModelContext) {
        phase = .failed
        lastErrorMessage = error.localizedDescription
        summary = nil
        issueMessages = [error.localizedDescription]
        isRunning = false
        isCancelling = false
        currentKind = nil
        task = nil
        pendingLinkedFolderSync = nil
        refreshInboxPendingCount()
        sendImportNotification(
            phase: .failed,
            summary: nil,
            errorMessage: error.localizedDescription
        )
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
        requestInboxScan(modelContext: modelContext)
        startNextQueuedWiFiImportIfNeeded(modelContext: modelContext)
    }

    /// Maps the run summary into the package value type, asks the pure policy,
    /// and hands the decision to the delivery hook. `isEnabled` and foreground
    /// gating live here; delivery only checks system authorization.
    private func sendImportNotification(
        phase: ImportPhase,
        summary: RunSummary?,
        errorMessage: String?
    ) {
        let snapshot = summary.map {
            ImportNotificationSummary(
                collectionName: $0.collectionName,
                importedCount: $0.importedCount,
                relinkedCount: $0.relinkedCount,
                failedCount: $0.failedCount,
                cancelled: $0.cancelled || phase == .cancelled,
                firstIssueMessage: $0.messages.first
            )
        }
        let decision = ImportNotificationPolicy.decision(
            summary: snapshot,
            errorMessage: errorMessage,
            isAppActive: Self.isAppActiveForImportNotifications(),
            isEnabled: AppSettingsStore().importNotificationsEnabled
        )
        // Always hand over the decision (including .none): the delivery hook
        // is also the DEBUG seam that records foreground/disabled decisions.
        deliverImportNotification?(decision)
    }

    /// Foreground imports already show their result in the import UI, so they
    /// do not post a banner. The DEBUG switch lets the UI suite exercise the
    /// real wiring while the app is technically active.
    private static func isAppActiveForImportNotifications() -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(
            "--p2-force-inactive-for-notifications"
        ) {
            return false
        }
        #endif
        #if os(iOS)
        return UIApplication.shared.applicationState == .active
        #else
        return false
        #endif
    }
}
