import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import LocalPodKit

struct ImportView: View {
    /// Pushed inside Settings (its NavigationStack) instead of owning one.
    var embedded = false

    private enum ActiveSheet: String, Identifiable {
        case folder
        case report
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(ImportCoordinator.self) private var coordinator
    @Query(sort: \MediaItem.addedAt, order: .reverse)
    private var allItems: [MediaItem]

    @State private var activeSheet: ActiveSheet?
    @State private var showWiFiUpload = false

    private var importedItems: [MediaItem] {
        allItems.filter { $0.source != .benchmark }
    }

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                NavigationStack {
                    content
                }
            }
        }
    }

    private var content: some View {
        List {
                Section {
                    TapeCard {
                        VStack(alignment: .leading, spacing: TapeTheme.space3) {
                            HStack(alignment: .firstTextBaseline) {
                                TapeKicker(text: "FOLDERS")
                                Spacer(minLength: 8)
                                Text("AUDIO ONLY")
                                    .font(TapeType.monoMicro)
                                    .foregroundStyle(TapeTheme.faint)
                            }
                            Text("把声音装进磁带盒")
                                .font(TapeType.title3)
                                .foregroundStyle(TapeTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("扫描文件夹及子文件夹；视频文件只取音轨，不显示画面。")
                                .font(TapeType.caption)
                                .foregroundStyle(TapeTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                activeSheet = .folder
                            } label: {
                                Label("选择文件夹（文件 App）", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(TapePrimaryButtonStyle())
                            .disabled(coordinator.isRunning)
                            .opacity(coordinator.isRunning ? 0.5 : 1)
                            .accessibilityIdentifier("chooseFolderButton")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tapeRowInsets(6)
                }

                if hasImportStatus {
                    Section {
                        TapeCard {
                            ImportStatusView()
                        }
                        .tapeRowInsets(6)
                    } header: {
                        sectionHeader(title: L10n.string("导入状态"), kicker: "STATUS")
                    } footer: {
                        Text("文件夹以原地读取方式播放，不会复制文件。导入期间请保持 App 在前台。")
                            .font(TapeType.captionSmall)
                            .foregroundStyle(TapeTheme.muted)
                            .padding(.horizontal, TapeTheme.space4)
                            .padding(.top, TapeTheme.space1)
                            .listRowBackground(Color.clear)
                    }
                }

                if let summary = coordinator.summary {
                    resultSection(summary)
                }

                if !coordinator.issueMessages.isEmpty {
                    Section {
                        TapeCard {
                            VStack(alignment: .leading, spacing: TapeTheme.space2) {
                                ForEach(Array(coordinator.issueMessages.prefix(20)), id: \.self) { message in
                                    Text(message)
                                        .font(TapeType.captionSmall)
                                        .foregroundStyle(TapeTheme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if coordinator.issueMessages.count > 20 {
                                    Text("另有 \(coordinator.issueMessages.count - 20) 条未显示")
                                        .font(TapeType.monoMicro)
                                        .foregroundStyle(TapeTheme.faint)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .tapeRowInsets(6)
                    } header: {
                        sectionHeader(title: L10n.string("问题与跳过"), kicker: "ISSUES")
                    }
                }

                Section {
                    if importedItems.isEmpty {
                        TapeDashedCard {
                            VStack(spacing: TapeTheme.space2) {
                                Text("还没有导入内容")
                                    .font(TapeType.body)
                                    .foregroundStyle(TapeTheme.ink)
                                    .accessibilityIdentifier("importRecentEmptyState")
                                Text("点上方「选择文件夹」开始；子文件夹会被递归扫描，文件保留在原位置。")
                                    .font(TapeType.captionSmall)
                                    .foregroundStyle(TapeTheme.muted)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .tapeRowInsets(6)
                    } else {
                        TapeCard {
                            VStack(spacing: TapeTheme.space1) {
                                ForEach(Array(importedItems.prefix(5))) { item in
                                    LibraryItemRow(item: item)
                                }
                                if importedItems.count > 5 {
                                    Text("共 \(importedItems.count) 条，完整资料库见「资料库」标签。")
                                        .font(TapeType.captionSmall)
                                        .foregroundStyle(TapeTheme.muted)
                                }
                            }
                        }
                        .tapeRowInsets(6)
                    }

                    Button {
                        showWiFiUpload = true
                    } label: {
                        TapeRow(
                            thumbText: "W",
                            thumbFill: TapeTheme.violet,
                            icon: "wifi",
                            title: L10n.string("import.wifi.title"),
                            subtitle: L10n.string("import.wifi.subtitle"),
                            trailingIcon: "chevron.right"
                        )
                    }
                    .buttonStyle(TapePlainPressStyle())
                    .accessibilityIdentifier("wifiUploadImportLink")
                    .tapeRowInsets(4)
                } header: {
                    if !importedItems.isEmpty {
                        sectionHeader(title: L10n.string("最近导入"), kicker: "RECENT TAPES")
                    }
                }
            }
            .listStyle(.plain)
            .tapeScreen()
            .navigationTitle("导入与文件夹")
            .tapeNavigationChrome()
            .accessibilityIdentifier("importScreen")
            .navigationDestination(isPresented: $showWiFiUpload) {
                WiFiUploadView()
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .folder:
                    DocumentPicker(
                        contentTypes: [.folder],
                        onPick: { urls in
                            activeSheet = nil
                            guard let url = urls.first else { return }
                            coordinator.startFolderImport(url, modelContext: modelContext)
                        },
                        onCancel: { activeSheet = nil }
                    )
                case .report:
                    ImportReportView(result: coordinator.lastResult)
                }
            }
    }

    private func sectionHeader(title: String, kicker: String) -> some View {
        TapeSectionHeader(title: title, kicker: kicker)
            .textCase(nil)
            .padding(.horizontal, TapeTheme.screenPadding)
            .padding(.top, TapeTheme.space3)
            .padding(.bottom, TapeTheme.space1)
    }

    /// Last run summary and live progress live at the top of the import page.
    private var hasImportStatus: Bool {
        coordinator.summary != nil
            || coordinator.phase != .idle
            || coordinator.isRunning
            || coordinator.lastErrorMessage != nil
    }

    private func resultSection(_ summary: ImportCoordinator.RunSummary) -> some View {
        Section {
            TapeCard {
                VStack(alignment: .leading, spacing: TapeTheme.space2) {
                    resultLine("来源", summary.kind.displayName)
                    resultLine("扫描", "\(summary.totalCandidates) 个文件")
                    resultLine("支持格式", "\(summary.supportedFiles) 个")
                    resultLine("导入", "\(summary.importedCount) 个")
                    if summary.relinkedCount > 0 {
                        resultLine("重链", "\(summary.relinkedCount) 个")
                    }
                    if summary.duplicateCount > 0 {
                        resultLine("重复跳过", "\(summary.duplicateCount) 个")
                    }
                    if summary.unsupportedCount > 0 {
                        resultLine("不支持的格式", "\(summary.unsupportedCount) 个")
                    }
                    if summary.failedCount > 0 {
                        resultLine("失败", "\(summary.failedCount) 个")
                    }
                    resultLine("复制", formatBytes(summary.copiedBytes))
                    resultLine("耗时", L10n.format("import.durationSeconds", summary.duration))
                    if let reportPath = summary.reportPath {
                        Text("报告：\(reportPath)")
                            .font(TapeType.monoMicro)
                            .foregroundStyle(TapeTheme.faint)
                            .lineLimit(1)
                    }
                    if coordinator.lastResult != nil {
                        Button {
                            activeSheet = .report
                        } label: {
                            Label("查看完整报告", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(TapeSecondaryButtonStyle())
                        .accessibilityIdentifier("viewImportReportButton")
                    }
                    Button("清除结果") {
                        coordinator.clearResult()
                    }
                    .buttonStyle(TapePlainPressStyle())
                    .font(TapeType.monoMeta)
                    .foregroundStyle(TapeTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tapeRowInsets(6)
        } header: {
            sectionHeader(title: L10n.string("详细结果"), kicker: "DETAILS")
        }
    }

    private func resultLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(TapeType.caption)
                .foregroundStyle(TapeTheme.muted)
            Spacer(minLength: 8)
            Text(value)
                .font(TapeType.monoMeta)
                .foregroundStyle(TapeTheme.ink)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Shared import progress/summary card. Shown on the Import page and on the
/// Diagnostics page so a manual run can be triggered and watched from Settings.
struct ImportStatusView: View {
    @Environment(ImportCoordinator.self) private var coordinator

    var body: some View {
        VStack(alignment: .leading, spacing: TapeTheme.space2) {
            if let summary = coordinator.summary {
                VStack(alignment: .leading, spacing: 2) {
                    Text("上次结果")
                        .font(TapeType.monoMeta)
                        .foregroundStyle(TapeTheme.faint)
                    Text("导入 \(summary.importedCount) · 重复 \(summary.duplicateCount) · 不支持 \(summary.unsupportedCount) · 失败 \(summary.failedCount)")
                        .font(TapeType.body)
                        .foregroundStyle(TapeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("importCategorySummary")
                }
                if summary.cancelled {
                    Text("任务已取消，已完成导入的文件会保留。")
                        .font(TapeType.captionSmall)
                        .foregroundStyle(TapeTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("importCancelledText")
                }
            }

            if coordinator.phase != .idle || coordinator.isRunning {
                HStack {
                    Text(coordinator.currentKind?.displayName ?? L10n.string("common.import"))
                        .font(TapeType.monoMeta)
                        .foregroundStyle(TapeTheme.muted)
                    Spacer(minLength: 8)
                    Text(coordinator.isCancelling ? L10n.string("正在取消…") : coordinator.phase.displayName)
                        .font(TapeType.monoMeta)
                        .foregroundStyle(TapeTheme.muted)
                }

                if let progress = coordinator.progress {
                    ProgressView(value: progress.fractionCompleted)
                        .tint(TapeTheme.ink)
                    Text("文件 \(progress.completedFiles)/\(progress.totalFiles) · \(formatBytes(progress.copiedBytes)) / \(formatBytes(progress.totalBytes))")
                        .font(TapeType.monoMicro)
                        .foregroundStyle(TapeTheme.muted)
                        .accessibilityIdentifier("importProgressText")
                    if let name = progress.currentFileName {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name)
                                .font(TapeType.monoMicro)
                                .foregroundStyle(TapeTheme.faint)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if progress.phase == .downloading {
                                if let fraction = progress.currentFileDownloadFraction {
                                    ProgressView(value: fraction)
                                        .tint(TapeTheme.ink)
                                } else {
                                    ProgressView()
                                }
                                Text("正在从 iCloud 下载…")
                                    .font(TapeType.captionSmall)
                                    .foregroundStyle(TapeTheme.muted)
                            }
                        }
                    }
                } else if coordinator.isRunning {
                    ProgressView()
                        .tint(TapeTheme.ink)
                }

                if coordinator.isRunning {
                    Button(role: .destructive) {
                        coordinator.cancel()
                    } label: {
                        Label(
                            coordinator.isCancelling ? "正在取消…" : "取消导入",
                            systemImage: "xmark.circle"
                        )
                    }
                    .buttonStyle(TapeDestructiveButtonStyle())
                    .disabled(coordinator.isCancelling)
                    .accessibilityIdentifier("cancelImportButton")
                }
            }

            if let error = coordinator.lastErrorMessage {
                VStack(alignment: .leading, spacing: 3) {
                    Text("导入遇到问题。请确认文件仍在本机、格式受支持且存储空间充足，然后重试。")
                        .font(TapeType.captionSmall)
                        .foregroundStyle(TapeTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("importErrorHeadline")
                    Text(error)
                        .font(TapeType.monoMicro)
                        .foregroundStyle(TapeTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("importErrorDetail")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }


    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct ImportReportView: View {
    let result: FolderImportResult?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let report = result?.report {
                    Section("汇总") {
                        LabeledContent("来源", value: report.source.displayName)
                        LabeledContent("扫描文件", value: "\(report.totalCandidates) 个")
                        LabeledContent("支持格式", value: "\(report.supportedFiles) 个")
                        LabeledContent("导入", value: "\(report.importedCount) 个")
                        if report.relinkedCount > 0 {
                            LabeledContent("重链", value: "\(report.relinkedCount) 个")
                        }
                        LabeledContent("重复", value: "\(report.duplicateCount) 个")
                        LabeledContent("不支持", value: "\(report.unsupportedCount) 个")
                        LabeledContent("失败", value: "\(report.failedCount) 个")
                        LabeledContent("总大小", value: ByteCountFormatter.string(
                            fromByteCount: report.totalBytes,
                            countStyle: .file
                        ))
                        LabeledContent("已复制", value: ByteCountFormatter.string(
                            fromByteCount: report.copiedBytes,
                            countStyle: .file
                        ))
                        if report.cancelled {
                            Text("导入已取消")
                                .foregroundStyle(.orange)
                        }
                    }

                    issueSection(
                        L10n.string("import.issue.section.duplicates"),
                        issues: report.duplicateIssues
                    )
                    issueSection(
                        L10n.string("import.issue.section.unsupported"),
                        issues: report.unsupportedIssues
                    )
                    issueSection(
                        L10n.string("import.issue.section.failures"),
                        issues: report.failureIssues
                    )
                } else {
                    ContentUnavailableView(
                        "没有报告",
                        systemImage: "doc.text",
                        description: Text("完成一次导入后这里会显示分类报告。")
                    )
                }
            }
            .navigationTitle("导入报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func issueSection(_ title: String, issues: [ImportIssue]) -> some View {
        if !issues.isEmpty {
            Section("\(title) · \(issues.count)") {
                ForEach(issues) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            issue.relativePath.isEmpty
                                ? L10n.string("import.issue.wholeRun")
                                : issue.relativePath
                        )
                            .font(.callout)
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
