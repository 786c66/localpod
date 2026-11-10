import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import LocalPodKit

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ImportCoordinator.self) private var coordinator
    @State private var showFilePicker = false

    private var inboxPath: String {
        ImportInbox.live.directoryURL.path
    }

    private var inboxSummary: ImportCoordinator.RunSummary? {
        guard let summary = coordinator.summary,
              summary.kind == .inbox || summary.kind == .openURL else {
            return nil
        }
        return summary
    }

    private var showsEmptyState: Bool {
        coordinator.inboxPendingCount == 0
            && coordinator.inboxUnstableCount == 0
            && coordinator.inboxSkippedCount == 0
            && inboxSummary == nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("待处理", value: "\(coordinator.inboxPendingCount) 个")
                    Text("待处理 \(coordinator.inboxPendingCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("inboxPendingCount")
                    LabeledContent("未稳定", value: "\(coordinator.inboxUnstableCount) 个")
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("inboxStabilityText")
                    LabeledContent("已隔离不支持文件", value: "\(coordinator.inboxSkippedCount) 个")
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("inboxSkippedCount")
                    Button {
                        coordinator.scanInboxNow(modelContext: modelContext)
                    } label: {
                        Label("立即扫描并导入收件箱", systemImage: "arrow.clockwise")
                    }
                    .disabled(coordinator.isRunning)

                    if coordinator.inboxHasPendingFailures {
                        Text("有文件未能导入。请确认格式受支持、文件已下载，然后点「重试失败」。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("inboxFailureHeadline")

                        Button {
                            coordinator.retryInboxFailures(modelContext: modelContext)
                        } label: {
                            Label("重试失败", systemImage: "arrow.clockwise.circle")
                        }
                        .disabled(coordinator.isRunning)
                        .accessibilityIdentifier("inboxRetryButton")

                        Text("自动重试已暂停；重试失败或放入新文件后会继续。")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("inboxAutoRetrySuspendedText")
                    }

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("选择单个文件投入收件箱", systemImage: "doc.badge.plus")
                    }
                    .disabled(coordinator.isRunning)
                } header: {
                    Text("收件箱")
                } footer: {
                    Text("收件箱是 Documents/Import。App 启动、回到前台以及前台运行期间会每 2 秒扫描一次；只有文件大小稳定后才会导入，不支持的文件会移入隐藏的 .Skipped 隔离目录。")
                }

                if showsEmptyState {
                    Section {
                        ContentUnavailableView {
                            Label("收件箱为空", systemImage: "tray")
                                .accessibilityIdentifier("inboxEmptyState")
                        } description: {
                            Text("用 Finder 拖入文件，或在下方选择文件；导入完成后会出现在资料库。")
                        } actions: {
                            Button("选择文件") {
                                showFilePicker = true
                            }
                            .disabled(coordinator.isRunning)
                            .accessibilityIdentifier("inboxEmptyPickFileButton")
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }
                }

                if coordinator.isRunning {
                    Section("当前任务") {
                        HStack {
                            Text(coordinator.currentKind?.displayName ?? L10n.string("common.import"))
                            Spacer()
                            Text(coordinator.isCancelling ? L10n.string("正在取消…") : coordinator.phase.displayName)
                                .foregroundStyle(.secondary)
                        }
                        if let progress = coordinator.progress {
                            ProgressView(value: progress.fractionCompleted)
                            Text("\(progress.completedFiles)/\(progress.totalFiles) 个文件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button(role: .destructive) {
                            coordinator.cancel()
                        } label: {
                            Label("取消", systemImage: "xmark.circle")
                        }
                        .disabled(coordinator.isCancelling)
                    }
                }

                if let error = coordinator.lastErrorMessage,
                   !coordinator.inboxHasPendingFailures {
                    Section("需要处理") {
                        Text("上一次操作未完成。请确认文件格式受支持且已下载，然后重试。")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("inboxErrorHeadline")
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("inboxErrorDetail")
                    }
                }

                if let summary = coordinator.summary,
                   summary.kind == .inbox || summary.kind == .openURL {
                    Section("上次结果") {
                        Text("导入 \(summary.importedCount) · 重复 \(summary.duplicateCount) · 不支持 \(summary.unsupportedCount) · 失败 \(summary.failedCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("inboxCategorySummary")
                        LabeledContent("导入", value: "\(summary.importedCount) 个")
                        if summary.duplicateCount > 0 {
                            LabeledContent("重复", value: "\(summary.duplicateCount) 个")
                        }
                        if summary.unsupportedCount > 0 {
                            LabeledContent("不支持", value: "\(summary.unsupportedCount) 个")
                        }
                        if summary.failedCount > 0 {
                            LabeledContent("失败", value: "\(summary.failedCount) 个")
                        }
                        LabeledContent("复制", value: ByteCountFormatter.string(
                            fromByteCount: summary.copiedBytes,
                            countStyle: .file
                        ))
                        if let reportPath = summary.reportPath {
                            Text("运行报告：\(reportPath)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .accessibilityIdentifier("inboxRunReportPath")
                        }
                        if summary.cancelled {
                            Text("任务已取消")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section("Finder 文件共享") {
                    Text("1. 用数据线连接 iPhone 与 Mac。")
                    Text("2. 在 Finder 侧边栏选择 iPhone →「文件」→ LocalPod。")
                    Text("3. 把音频/视频拖进 Import 文件夹。")
                    Text("4. 回到 App 后会自动扫描；也可点上面的「立即扫描」。")
                }
                .font(.callout)

                Section("外部打开") {
                    Text("在文件 App 中长按音频/视频 →「共享」→ LocalPod。")
                    Text("App 会先把文件放进收件箱，再走同一条导入流水线。")
                }
                .font(.callout)

                Section("收件箱路径") {
                    Text(inboxPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("收件箱")
            .task {
                coordinator.refreshInboxPendingCount()
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPicker(
                    contentTypes: SupportedMedia.contentTypes,
                    onPick: { urls in
                        showFilePicker = false
                        guard let url = urls.first else { return }
                        coordinator.stageAndImportFile(url, kind: .inbox, modelContext: modelContext)
                    },
                    onCancel: { showFilePicker = false }
                )
            }
        }
    }
}
