import Foundation
import SwiftUI
import SwiftData
import UIKit
import LocalPodKit

struct DiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ImportCoordinator.self) private var coordinator

    @State private var importedCount = 0
    @State private var benchmarkCount = 0
    @State private var collectionCount = 0
    @State private var sessionCount = 0
    @State private var missingCount = 0
    @State private var libraryBytes: Int64 = 0
    @State private var signingInfo: SigningInfo?
    @State private var inboxPath = ""
    @State private var mediaPath = ""
    @State private var supportPath = ""
    @State private var copied = false

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "—"
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private var deviceDescription: String {
        #if os(iOS)
        "\(UIDevice.current.model) · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #else
        ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let info = signingInfo, let days = info.daysRemaining {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: days <= 2 ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                                .foregroundStyle(days <= 2 ? Color.orange : Color.green)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(signingBannerText(days: days))
                                    .font(.callout)
                                    .accessibilityIdentifier("signingExpiryBanner")
                                Text("到期：\(info.expirationDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("工具") {
                    NavigationLink {
                        BenchmarkView()
                    } label: {
                        Label("SwiftData 5k 基准", systemImage: "gauge.with.dots.needle.67percent")
                    }
                    .accessibilityIdentifier("benchmarkLink")
                }

                Section {
                    if let summary = coordinator.lastCleanupSummary {
                        Text(summary.hasChanges ? "启动维护已完成。" : "启动维护已完成，没有需要清理的内容。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("maintenanceSummaryText")
                        Text("staging \(summary.stagingSessionsRemoved) · 孤儿媒体 \(summary.orphanMediaFilesRemoved) · 孤儿封面 \(summary.orphanArtworkFilesRemoved) · 缺失 \(summary.missingMarked)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("maintenanceDetailText")
                        LabeledContent("标记缺失", value: "\(summary.missingMarked)")
                        LabeledContent("恢复存在", value: "\(summary.restored)")
                        LabeledContent("清理孤儿媒体", value: "\(summary.orphanMediaFilesRemoved)")
                        LabeledContent("清理 staging", value: "\(summary.stagingSessionsRemoved)")
                        LabeledContent("清理孤儿封面", value: "\(summary.orphanArtworkFilesRemoved)")
                        LabeledContent("清理过期回收站", value: "\(summary.expiredTrashPurged)")
                        if !summary.failures.isEmpty {
                            ForEach(summary.failures, id: \.self) { failure in
                                Text(failure)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    } else {
                        Text("尚未运行启动维护。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        coordinator.runMaintenance(modelContext: modelContext)
                        refresh()
                    } label: {
                        Label("立即对账 / 清理", systemImage: "cross.case")
                    }
                    .disabled(coordinator.isRunning)
                    .accessibilityIdentifier("runMaintenanceButton")

                } header: {
                    Text("维护")
                } footer: {
                    Text("启动、回前台或手动触发：缺失文件标记、孤儿媒体/封面清理、残留 staging 清理。导入进行中不执行。")
                }

                Section("App") {
                    LabeledContent("Bundle ID", value: bundleIdentifier)
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("设备", value: deviceDescription)
                }

                Section {
                    if let info = signingInfo {
                        LabeledContent("描述文件", value: info.name ?? "—")
                        LabeledContent("Team", value: info.teamIdentifier ?? "—")
                        LabeledContent("App ID", value: info.appIdentifier ?? "—")
                        if let expiration = info.expirationDate {
                            LabeledContent(
                                "到期",
                                value: expiration.formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                        if let days = info.daysRemaining {
                            LabeledContent(
                                "剩余",
                                value: days >= 0
                                    ? L10n.format("diagnostics.daysRemaining", days)
                                    : L10n.format("diagnostics.daysExpired", -days)
                            )
                        }
                        if let deviceCount = info.provisionedDeviceCount {
                            LabeledContent("描述文件设备数", value: "\(deviceCount)")
                        }
                        Text(info.statusText)
                            .font(.caption)
                            .foregroundStyle(info.isExpired ? .red : .green)
                    } else {
                        Text("未发现 embedded.mobileprovision（模拟器或未签名构建）。真机免费账号构建会显示 7 天到期时间。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("签名")
                } footer: {
                    Text("免费 Apple ID 的 Personal Team 描述文件通常 7 天到期。到期后 App 无法启动；用同一 Bundle ID 在 Xcode 重新运行即可，App 容器数据一般保留。")
                }

                Section("数据") {
                    LabeledContent("资料库条目", value: "\(importedCount) 条")
                    LabeledContent("缺失条目", value: "\(missingCount) 条")
                    LabeledContent("合集", value: "\(collectionCount) 个")
                    LabeledContent("导入会话", value: "\(sessionCount) 次")
                    LabeledContent("资料库大小", value: ByteCountFormatter.string(
                        fromByteCount: libraryBytes,
                        countStyle: .file
                    ))
                    LabeledContent("基准条目", value: "\(benchmarkCount) 条")
                }

                Section("路径") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("收件箱 (Documents/Import)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(inboxPath)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("媒体库 (Application Support/Media)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(mediaPath)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Application Support")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(supportPath)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                }

                Section {
                    Button {
                        refresh()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    Button {
                        UIPasteboard.general.string = diagnosticText
                        copied = true
                    } label: {
                        Label(copied ? "已复制诊断信息" : "复制诊断信息", systemImage: copied ? "checkmark.circle" : "doc.on.doc")
                    }
                }
            }
            .navigationTitle("诊断")
            .task {
                refresh()
            }
        }
    }

    private var diagnosticText: String {
        var lines = [
            L10n.string("diagnostics.title"),
            L10n.format("diagnostics.line.bundleID", bundleIdentifier),
            L10n.format("diagnostics.line.version", appVersion),
            L10n.format("diagnostics.line.device", deviceDescription),
            L10n.format("diagnostics.line.library", importedCount),
            L10n.format("diagnostics.line.missing", missingCount),
            L10n.format("diagnostics.line.collections", collectionCount),
            L10n.format("diagnostics.line.sessions", sessionCount),
            L10n.format(
                "diagnostics.line.librarySize",
                ByteCountFormatter.string(fromByteCount: libraryBytes, countStyle: .file)
            ),
            L10n.format("diagnostics.line.benchmark", benchmarkCount),
            L10n.format("diagnostics.line.inbox", inboxPath),
            L10n.format("diagnostics.line.media", mediaPath)
        ]
        if let info = signingInfo {
            lines.append(L10n.format("diagnostics.line.profile", info.name ?? "—"))
            lines.append(L10n.format("diagnostics.line.team", info.teamIdentifier ?? "—"))
            lines.append(L10n.format("diagnostics.line.appID", info.appIdentifier ?? "—"))
            if let expiration = info.expirationDate {
                lines.append(L10n.format(
                    "diagnostics.line.expiration",
                    expiration.formatted(date: .abbreviated, time: .shortened)
                ))
            }
            if let days = info.daysRemaining {
                lines.append(L10n.format("diagnostics.line.remaining", days))
            }
        } else {
            lines.append(L10n.string("diagnostics.line.profileMissing"))
        }
        return lines.joined(separator: "\n")
    }

    private func signingBannerText(days: Int) -> String {
        if days < 0 {
            return L10n.format("diagnostics.signing.expired", -days)
        }
        if days == 0 {
            return L10n.string("diagnostics.signing.today")
        }
        return L10n.format("diagnostics.signing.days", days)
    }

    private func refresh() {
        signingInfo = SigningInfo.current()
        inboxPath = ImportInbox.live.directoryURL.path
        supportPath = MediaStorage.live.applicationSupportRoot.path
        mediaPath = (try? MediaStorage.live.mediaRootURL().path) ?? "—"
        importedCount = (try? modelContext.fetchCount(
            FetchDescriptor<MediaItem>(predicate: #Predicate { $0.sourceRaw != "benchmark" })
        )) ?? 0
        benchmarkCount = (try? modelContext.fetchCount(
            FetchDescriptor<MediaItem>(predicate: #Predicate { $0.sourceRaw == "benchmark" })
        )) ?? 0
        collectionCount = (try? modelContext.fetchCount(FetchDescriptor<MediaCollection>())) ?? 0
        sessionCount = (try? modelContext.fetchCount(FetchDescriptor<ImportSession>())) ?? 0
        missingCount = (try? modelContext.fetchCount(
            FetchDescriptor<MediaItem>(predicate: #Predicate { $0.isMissing })
        )) ?? 0
        libraryBytes = (try? modelContext.fetch(FetchDescriptor<MediaItem>())
            .filter { $0.source != .benchmark }
            .reduce(into: Int64(0)) { $0 += $1.byteSize }) ?? 0
        copied = false
    }
}
