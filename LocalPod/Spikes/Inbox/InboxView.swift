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
                // The queue card, the last result and errors sit above the
                // explanatory hero: this screen is where an import finishes,
                // and a List only realises rows inside the viewport. The
                // inline scan actions stay reachable one card lower.
                Section {
                    countCard
                        .tapeRowInsets(6)
                    if coordinator.inboxHasPendingFailures {
                        failureCard
                            .tapeRowInsets(6)
                    }
                }

                if let error = coordinator.lastErrorMessage,
                   !coordinator.inboxHasPendingFailures {
                    errorSection(error)
                }

                if let summary = inboxSummary {
                    resultSection(summary)
                }

                if showsEmptyState {
                    Section {
                        TapeDashedCard {
                            VStack(spacing: TapeTheme.space3) {
                                TapeRewardSticker(
                                    text: "EMPTY",
                                    fill: TapeTheme.violet,
                                    foreground: TapeTheme.stickerInk
                                )
                                Text("收件箱为空")
                                    .font(TapeType.title2)
                                    .tracking(-0.4)
                                    .foregroundStyle(TapeTheme.ink)
                                    .multilineTextAlignment(.center)
                                    .accessibilityIdentifier("inboxEmptyState")
                                Text("用 Finder 拖入文件，或在下方选择文件；导入完成后会出现在资料库。")
                                    .font(TapeType.body)
                                    .foregroundStyle(TapeTheme.muted)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("选择文件") {
                                    showFilePicker = true
                                }
                                .buttonStyle(TapeSecondaryButtonStyle())
                                .disabled(coordinator.isRunning)
                                .opacity(coordinator.isRunning ? 0.5 : 1)
                                .accessibilityIdentifier("inboxEmptyPickFileButton")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .tapeRowInsets(6)
                    }
                }

                Section {
                    heroCard
                        .tapeRowInsets(8)
                } header: {
                    sectionHeader("收件箱", kicker: "DROP ZONE")
                }

                if coordinator.isRunning {
                    currentTaskSection
                }

                Section {
                    TapeCard {
                        VStack(alignment: .leading, spacing: TapeTheme.space2) {
                            Text("1. 用数据线连接 iPhone 与 Mac。")
                            Text("2. 在 Finder 侧边栏选择 iPhone →「文件」→ LocalPod。")
                            Text("3. 把音频/视频拖进 Import 文件夹。")
                            Text("4. 回到 App 后会自动扫描；也可点上面的「立即扫描」。")
                        }
                        .font(TapeType.bodySmall)
                        .foregroundStyle(TapeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tapeRowInsets(6)
                } header: {
                    sectionHeader("Finder 文件共享", kicker: "FINDER")
                }

                Section {
                    TapeCard {
                        VStack(alignment: .leading, spacing: TapeTheme.space2) {
                            Text("在文件 App 中长按音频/视频 →「共享」→ LocalPod。")
                            Text("App 会先把文件放进收件箱，再走同一条导入流水线。")
                        }
                        .font(TapeType.bodySmall)
                        .foregroundStyle(TapeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tapeRowInsets(6)
                } header: {
                    sectionHeader("外部打开", kicker: "OPEN IN")
                }

                Section {
                    TapeCard {
                        Text(inboxPath)
                            .font(TapeType.monoMeta)
                            .foregroundStyle(TapeTheme.muted)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tapeRowInsets(6)
                } header: {
                    sectionHeader("收件箱路径", kicker: "ON DISK")
                }
            }
            .listStyle(.plain)
            .tapeScreen()
            .navigationTitle("收件箱")
            .tapeNavigationChrome()
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

    // MARK: - Header cards

    private var heroCard: some View {
        TapeCard(fill: TapeTheme.violetSoft) {
            VStack(alignment: .leading, spacing: TapeTheme.space3) {
                HStack(alignment: .center, spacing: TapeTheme.space2) {
                    TapeSticker(
                        text: "INBOX",
                        fill: TapeTheme.violet,
                        foreground: TapeTheme.stickerInk
                    )
                    Spacer(minLength: TapeTheme.space2)
                    Text("AUTO SCAN · 2S")
                        .font(TapeType.monoMicro)
                        .foregroundStyle(TapeTheme.ink.opacity(0.62))
                }

                Text("收件箱是 Documents/Import。App 启动、回到前台以及前台运行期间会每 2 秒扫描一次；只有文件大小稳定后才会导入，不支持的文件会移入隐藏的 .Skipped 隔离目录。")
                    .font(TapeType.body)
                    .foregroundStyle(TapeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: TapeTheme.space2) {
                    Button {
                        coordinator.scanInboxNow(modelContext: modelContext)
                    } label: {
                        Label("立即扫描并导入收件箱", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(TapePrimaryButtonStyle())
                    .disabled(coordinator.isRunning)
                    .opacity(coordinator.isRunning ? 0.5 : 1)

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("选择单个文件投入收件箱", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(TapeSecondaryButtonStyle())
                    .disabled(coordinator.isRunning)
                    .opacity(coordinator.isRunning ? 0.5 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var countCard: some View {
        TapeCard {
            VStack(alignment: .leading, spacing: TapeTheme.space3) {
                HStack(alignment: .firstTextBaseline, spacing: TapeTheme.space2) {
                    TapeKicker(text: "QUEUE")
                    Spacer(minLength: TapeTheme.space2)
                    Text("待处理 \(coordinator.inboxPendingCount)")
                        .font(TapeType.monoMicro)
                        .foregroundStyle(TapeTheme.faint)
                        .accessibilityIdentifier("inboxPendingCount")
                }

                countRow("待处理", value: "\(coordinator.inboxPendingCount) 个")
                TapeHairline()
                countRow("未稳定", value: "\(coordinator.inboxUnstableCount) 个")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("inboxStabilityText")
                TapeHairline()
                countRow("已隔离不支持文件", value: "\(coordinator.inboxSkippedCount) 个")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("inboxSkippedCount")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var failureCard: some View {
        TapeCard {
            VStack(alignment: .leading, spacing: TapeTheme.space3) {
                HStack(alignment: .top, spacing: TapeTheme.space2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(TapeTheme.coral)
                        .accessibilityHidden(true)
                    Text("有文件未能导入。请确认格式受支持、文件已下载，然后点「重试失败」。")
                        .font(TapeType.body)
                        .foregroundStyle(TapeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("inboxFailureHeadline")
                }

                Button {
                    coordinator.retryInboxFailures(modelContext: modelContext)
                } label: {
                    Label("重试失败", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(TapeSecondaryButtonStyle())
                .disabled(coordinator.isRunning)
                .opacity(coordinator.isRunning ? 0.5 : 1)
                .accessibilityIdentifier("inboxRetryButton")

                Text("自动重试已暂停；重试失败或放入新文件后会继续。")
                    .font(TapeType.captionSmall)
                    .foregroundStyle(TapeTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inboxAutoRetrySuspendedText")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Live task

    private var currentTaskSection: some View {
        Section {
            TapeCard {
                VStack(alignment: .leading, spacing: TapeTheme.space3) {
                    HStack(alignment: .firstTextBaseline, spacing: TapeTheme.space2) {
                        Text(coordinator.currentKind?.displayName ?? L10n.string("common.import"))
                            .font(TapeType.headline)
                            .foregroundStyle(TapeTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: TapeTheme.space2)
                        Text(coordinator.isCancelling ? L10n.string("正在取消…") : coordinator.phase.displayName)
                            .font(TapeType.monoMeta)
                            .foregroundStyle(TapeTheme.muted)
                            .multilineTextAlignment(.trailing)
                    }

                    if let progress = coordinator.progress {
                        TapeProgressBar(progress: progress.fractionCompleted)
                        Text("\(progress.completedFiles)/\(progress.totalFiles) 个文件")
                            .font(TapeType.monoMicro)
                            .foregroundStyle(TapeTheme.muted)
                    }

                    Button(role: .destructive) {
                        coordinator.cancel()
                    } label: {
                        Label("取消", systemImage: "xmark.circle")
                    }
                    .buttonStyle(TapeDestructiveButtonStyle())
                    .disabled(coordinator.isCancelling)
                    .opacity(coordinator.isCancelling ? 0.5 : 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tapeRowInsets(6)
        } header: {
            sectionHeader("当前任务", kicker: "NOW RUNNING")
        }
    }

    // MARK: - Error and result

    private func errorSection(_ error: String) -> some View {
        Section {
            TapeCard {
                VStack(alignment: .leading, spacing: TapeTheme.space2) {
                    Text("上一次操作未完成。请确认文件格式受支持且已下载，然后重试。")
                        .font(TapeType.body)
                        .foregroundStyle(TapeTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("inboxErrorHeadline")
                    Text(error)
                        .font(TapeType.monoMicro)
                        .foregroundStyle(TapeTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("inboxErrorDetail")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tapeRowInsets(6)
        } header: {
            sectionHeader("需要处理", kicker: "TROUBLE")
        }
    }

    private func resultSection(_ summary: ImportCoordinator.RunSummary) -> some View {
        Section {
            TapeCard {
                VStack(alignment: .leading, spacing: TapeTheme.space2) {
                    Text("导入 \(summary.importedCount) · 重复 \(summary.duplicateCount) · 不支持 \(summary.unsupportedCount) · 失败 \(summary.failedCount)")
                        .font(TapeType.body)
                        .foregroundStyle(TapeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("inboxCategorySummary")

                    TapeHairline()

                    resultRow("导入", "\(summary.importedCount) 个")
                    if summary.duplicateCount > 0 {
                        resultRow("重复", "\(summary.duplicateCount) 个")
                    }
                    if summary.unsupportedCount > 0 {
                        resultRow("不支持", "\(summary.unsupportedCount) 个")
                    }
                    if summary.failedCount > 0 {
                        resultRow("失败", "\(summary.failedCount) 个")
                    }
                    resultRow("复制", ByteCountFormatter.string(
                        fromByteCount: summary.copiedBytes,
                        countStyle: .file
                    ))

                    if let reportPath = summary.reportPath {
                        Text("运行报告：\(reportPath)")
                            .font(TapeType.monoMicro)
                            .foregroundStyle(TapeTheme.faint)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityIdentifier("inboxRunReportPath")
                    }
                    if summary.cancelled {
                        Text("任务已取消")
                            .font(TapeType.captionSmall)
                            .foregroundStyle(TapeTheme.coral)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tapeRowInsets(6)
        } header: {
            sectionHeader("上次结果", kicker: "LAST RUN")
        }
    }

    // MARK: - Shared pieces

    private func sectionHeader(_ title: String, kicker: String) -> some View {
        TapeSectionHeader(title: title, kicker: kicker)
            .textCase(nil)
            .padding(.horizontal, TapeTheme.screenPadding)
            .padding(.top, TapeTheme.space3)
            .padding(.bottom, TapeTheme.space1)
    }

    private func countRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TapeTheme.space2) {
            Text(label)
                .font(TapeType.body)
                .foregroundStyle(TapeTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: TapeTheme.space2)
            Text(value)
                .font(TapeFont.mono(19, weight: .semibold, relativeTo: .title3))
                .foregroundStyle(TapeTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func resultRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TapeTheme.space2) {
            Text(label)
                .font(TapeType.bodySmall)
                .foregroundStyle(TapeTheme.muted)
            Spacer(minLength: TapeTheme.space2)
            Text(value)
                .font(TapeType.monoMeta)
                .foregroundStyle(TapeTheme.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
