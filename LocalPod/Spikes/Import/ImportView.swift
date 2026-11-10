import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import LocalPodKit

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ImportCoordinator.self) private var coordinator
    @Query(
        filter: #Predicate<MediaItem> { $0.sourceRaw == "import" },
        sort: \MediaItem.addedAt,
        order: .reverse
    )
    private var importedItems: [MediaItem]

    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showFolderPicker = true
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
                } header: {
                    Text("导入")
                } footer: {
                    Text("递归扫描选中的文件夹，只处理 UTType.audio 与 UTType.movie 支持的文件；文件复制进沙盒，不依赖原文件后续权限。演示文件夹放在 Application Support，不会出现在文件 App 中。")
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
                        Text("还没有导入条目。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(importedItems.prefix(5))) { item in
                            ImportedItemRow(item: item)
                        }
                        if importedItems.count > 5 {
                            Text("共 \(importedItems.count) 条，仅显示最近 5 条")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("资料库 · \(importedItems.count)")
                }
            }
            .navigationTitle("LocalPod")
            .accessibilityIdentifier("importScreen")
            .sheet(isPresented: $showFolderPicker) {
                DocumentPicker(
                    contentTypes: [.folder],
                    onPick: { urls in
                        showFolderPicker = false
                        guard let url = urls.first else { return }
                        coordinator.startFolderImport(url, modelContext: modelContext)
                    },
                    onCancel: { showFolderPicker = false }
                )
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
                if let name = progress.currentFileName {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
            }

            if let error = coordinator.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func resultSection(_ summary: ImportCoordinator.RunSummary) -> some View {
        Section("结果") {
            LabeledContent("来源", value: summary.kind.displayName)
            LabeledContent("导入", value: "\(summary.importedCount) 个")
            Text("已导入 \(summary.importedCount) 个文件")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("importSummaryCount")
            if summary.failedCount > 0 {
                LabeledContent("问题", value: "\(summary.failedCount) 条")
            }
            if summary.skippedUnsupportedCount > 0 {
                LabeledContent("不支持的格式", value: "\(summary.skippedUnsupportedCount) 个")
            }
            LabeledContent("复制", value: formatBytes(summary.copiedBytes))
            LabeledContent("耗时", value: String(format: "%.1f 秒", summary.duration))
            if summary.cancelled {
                Text("任务已取消，已完成复制并写入资料库的文件会保留。")
                    .font(.caption)
                    .foregroundStyle(.orange)
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

struct ImportedItemRow: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.isVideo ? "film" : "waveform")
                .foregroundStyle(item.kind.isVideo ? .orange : .indigo)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(1)
                Text("\(item.kind.displayName) · \(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))\(item.folderName.map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
