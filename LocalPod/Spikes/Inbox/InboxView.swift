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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("待处理", value: "\(coordinator.inboxPendingCount) 个")
                    Button {
                        coordinator.refreshInboxPendingCount()
                        coordinator.importInboxIfNeeded(modelContext: modelContext)
                    } label: {
                        Label("立即扫描并导入收件箱", systemImage: "arrow.clockwise")
                    }
                    .disabled(coordinator.isRunning)

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("选择单个文件投入收件箱", systemImage: "doc.badge.plus")
                    }
                    .disabled(coordinator.isRunning)
                } header: {
                    Text("收件箱")
                } footer: {
                    Text("收件箱是 Documents/Import。App 启动、回到前台或收到外部文件时会自动扫描；导入成功后会移除来源文件。")
                }

                if coordinator.isRunning {
                    Section("当前任务") {
                        HStack {
                            Text(coordinator.currentKind?.displayName ?? "导入")
                            Spacer()
                            Text(coordinator.isCancelling ? "正在取消…" : coordinator.phase.displayName)
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

                if let summary = coordinator.summary,
                   summary.kind == .inbox || summary.kind == .openURL {
                    Section("上次结果") {
                        LabeledContent("导入", value: "\(summary.importedCount) 个")
                        LabeledContent("问题", value: "\(summary.failedCount) 条")
                        LabeledContent("复制", value: ByteCountFormatter.string(
                            fromByteCount: summary.copiedBytes,
                            countStyle: .file
                        ))
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
