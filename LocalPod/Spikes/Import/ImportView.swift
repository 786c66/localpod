import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import LocalPodKit

struct ImportView: View {
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

    private var importedItems: [MediaItem] {
        allItems.filter { $0.source != .benchmark }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        coordinator.importSampleContent(modelContext: modelContext)
                    } label: {
                        Label("添加示例内容", systemImage: "sparkles")
                    }
                    .disabled(coordinator.isRunning || !coordinator.isSampleImportAvailable)
                    .accessibilityIdentifier("sampleAddButton")
                } header: {
                    Text("示例内容")
                } footer: {
                    Text("导入 3 段自生成的短语音示例，归入「示例内容」合集。可随时在设置中一键删除，不会影响你导入的内容。")
                }

                Section {
                    Button {
                        activeSheet = .folder
                    } label: {
                        Label("选择文件夹（文件 App）", systemImage: "folder.badge.plus")
                    }
                    .disabled(coordinator.isRunning)
                    .accessibilityIdentifier("chooseFolderButton")

                    Button {
                        coordinator.importDemoFolder(modelContext: modelContext)
                    } label: {
                        Label("导入内置演示文件夹（100 个文件，3 层）", systemImage: "testtube.2")
                    }
                    .disabled(coordinator.isRunning)
                    .accessibilityIdentifier("importDemoFolderButton")

                    #if DEBUG
                    Button {
                        coordinator.importAcceptanceFolder(modelContext: modelContext)
                    } label: {
                        Label("导入验收文件夹（100 文件，含 2 不支持 + 1 重复）", systemImage: "checklist")
                    }
                    .disabled(coordinator.isRunning)
                    .accessibilityIdentifier("importAcceptanceFolderButton")
                    #endif
                } header: {
                    Text("导入")
                } footer: {
                    Text("递归扫描选中的文件夹，只处理 UTType.audio 与 UTType.movie；文件复制进沙盒并计算 SHA-256，重复内容会跳过。导入中请保持 App 在前台。")
                }

                if let summary = coordinator.summary {
                    Section("上次结果") {
                        Text("导入 \(summary.importedCount) · 重复 \(summary.duplicateCount) · 不支持 \(summary.unsupportedCount) · 失败 \(summary.failedCount)")
                            .font(.callout)
                            .accessibilityIdentifier("importCategorySummary")
                        if summary.cancelled {
                            Text("任务已取消，已完成导入的文件会保留。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .accessibilityIdentifier("importCancelledText")
                        }
                    }
                }

                if coordinator.phase != .idle || coordinator.isRunning {
                    progressSection
                }

                if let summary = coordinator.summary {
                    resultSection(summary)
                }

                if !coordinator.issueMessages.isEmpty {
                    Section("问题与跳过") {
                        ForEach(Array(coordinator.issueMessages.prefix(20)), id: \.self) { message in
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if coordinator.issueMessages.count > 20 {
                            Text("另有 \(coordinator.issueMessages.count - 20) 条未显示")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section {
                    if importedItems.isEmpty {
                        ContentUnavailableView {
                            Label("还没有导入内容", systemImage: "tray.and.arrow.down")
                                .accessibilityIdentifier("importRecentEmptyState")
                        } description: {
                            Text("点上方「选择文件夹」开始；子文件夹会被递归扫描。")
                        } actions: {
                            Button("选择文件夹") {
                                activeSheet = .folder
                            }
                            .disabled(coordinator.isRunning)
                            .accessibilityIdentifier("importEmptyChooseFolderButton")
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(Array(importedItems.prefix(5))) { item in
                            LibraryItemRow(item: item)
                        }
                        if importedItems.count > 5 {
                            Text("共 \(importedItems.count) 条，完整资料库见「资料库」标签。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("最近导入")
                }
            }
            .navigationTitle("LocalPod")
            .accessibilityIdentifier("importScreen")
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
    }

    @ViewBuilder
    private var progressSection: some View {
        Section("进度") {
            HStack {
                Text(coordinator.currentKind?.displayName ?? "导入")
                Spacer()
                Text(coordinator.isCancelling ? "正在取消…" : coordinator.phase.displayName)
                    .foregroundStyle(.secondary)
            }

            if let progress = coordinator.progress {
                ProgressView(value: progress.fractionCompleted)
                Text("文件 \(progress.completedFiles)/\(progress.totalFiles) · \(formatBytes(progress.copiedBytes)) / \(formatBytes(progress.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("importProgressText")
                if let name = progress.currentFileName {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if progress.phase == .downloading {
                            if let fraction = progress.currentFileDownloadFraction {
                                ProgressView(value: fraction)
                            } else {
                                ProgressView()
                            }
                            Text("正在从 iCloud 下载…")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                ProgressView()
            }

            if coordinator.isRunning {
                Button(role: .destructive) {
                    coordinator.cancel()
                } label: {
                    Label(coordinator.isCancelling ? "正在取消…" : "取消导入", systemImage: "xmark.circle")
                }
                .disabled(coordinator.isCancelling)
                .accessibilityIdentifier("cancelImportButton")
            }

            if let error = coordinator.lastErrorMessage {
                VStack(alignment: .leading, spacing: 3) {
                    Text("导入遇到问题。请确认文件仍在本机、格式受支持且存储空间充足，然后重试。")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("importErrorHeadline")
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("importErrorDetail")
                }
            }
        }
    }

    private func resultSection(_ summary: ImportCoordinator.RunSummary) -> some View {
        Section("详细结果") {
            LabeledContent("来源", value: summary.kind.displayName)
            LabeledContent("扫描", value: "\(summary.totalCandidates) 个文件")
            LabeledContent("支持格式", value: "\(summary.supportedFiles) 个")
            LabeledContent("导入", value: "\(summary.importedCount) 个")
            if summary.relinkedCount > 0 {
                LabeledContent("重链", value: "\(summary.relinkedCount) 个")
            }
            if summary.duplicateCount > 0 {
                LabeledContent("重复跳过", value: "\(summary.duplicateCount) 个")
            }
            if summary.unsupportedCount > 0 {
                LabeledContent("不支持的格式", value: "\(summary.unsupportedCount) 个")
            }
            if summary.failedCount > 0 {
                LabeledContent("失败", value: "\(summary.failedCount) 个")
            }
            LabeledContent("复制", value: formatBytes(summary.copiedBytes))
            LabeledContent("耗时", value: String(format: "%.1f 秒", summary.duration))
            if let reportPath = summary.reportPath {
                Text("报告：\(reportPath)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if coordinator.lastResult != nil {
                Button {
                    activeSheet = .report
                } label: {
                    Label("查看完整报告", systemImage: "doc.text.magnifyingglass")
                }
                .accessibilityIdentifier("viewImportReportButton")
            }
            Button("清除结果") {
                coordinator.clearResult()
            }
        }
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

                    issueSection("重复", issues: report.duplicateIssues)
                    issueSection("不支持", issues: report.unsupportedIssues)
                    issueSection("失败", issues: report.failureIssues)
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
                        Text(issue.relativePath.isEmpty ? "（整体）" : issue.relativePath)
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
