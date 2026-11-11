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
    @State private var showBenchmark = false

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
                if let info = signingInfo, let days = info.daysRemaining {
                    Section {
                        signingCard(info: info, days: days)
                            .tapeRowInsets(6)
                    }
                }

                Section {
                    benchmarkLink
                } header: {
                    sectionHeader("工具", kicker: "TOOLS")
                }

                Section {
                    maintenanceCard
                } header: {
                    sectionHeader("维护", kicker: "MAINTENANCE")
                } footer: {
                    sectionFooter("启动、回前台或手动触发：缺失文件标记、孤儿媒体/封面清理、残留 staging 清理。导入进行中不执行。")
                }

                Section {
                    TapeCard {
                        VStack(spacing: TapeTheme.space2) {
                            infoRow("Bundle ID", bundleIdentifier)
                            TapeHairline()
                            infoRow("版本", appVersion)
                            TapeHairline()
                            infoRow("设备", deviceDescription)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tapeRowInsets(6)
                } header: {
                    sectionHeader("App", kicker: "APP INFO")
                }

                Section {
                    signingDetailCard
                } header: {
                    sectionHeader("签名", kicker: "SIGNING")
                } footer: {
                    sectionFooter("免费 Apple ID 的 Personal Team 描述文件通常 7 天到期。到期后 App 无法启动；用同一 Bundle ID 在 Xcode 重新运行即可，App 容器数据一般保留。")
                }

                Section {
                    TapeCard {
                        VStack(spacing: TapeTheme.space2) {
                            Group {
                                infoRow("资料库条目", "\(importedCount) 条")
                                TapeHairline()
                                infoRow("缺失条目", "\(missingCount) 条")
                                TapeHairline()
                                infoRow("合集", "\(collectionCount) 个")
                                TapeHairline()
                                infoRow("导入会话", "\(sessionCount) 次")
                                TapeHairline()
                                infoRow("资料库大小", ByteCountFormatter.string(
                                    fromByteCount: libraryBytes,
                                    countStyle: .file
                                ))
                                TapeHairline()
                            }
                            infoRow("基准条目", "\(benchmarkCount) 条")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tapeRowInsets(6)
                } header: {
                    sectionHeader("数据", kicker: "LIBRARY DATA")
                }

                Section {
                    TapeCard {
                        VStack(alignment: .leading, spacing: TapeTheme.space3) {
                            pathBlock("收件箱 (Documents/Import)", path: inboxPath)
                            TapeHairline()
                            pathBlock("媒体库 (Application Support/Media)", path: mediaPath)
                            TapeHairline()
                            pathBlock("Application Support", path: supportPath)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tapeRowInsets(6)
                } header: {
                    sectionHeader("路径", kicker: "ON DISK")
                }

                Section {
                    Button {
                        refresh()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(TapeSecondaryButtonStyle())
                    .tapeRowInsets(4)

                    Button {
                        UIPasteboard.general.string = diagnosticText
                        copied = true
                    } label: {
                        Label(copied ? "已复制诊断信息" : "复制诊断信息", systemImage: copied ? "checkmark.circle" : "doc.on.doc")
                    }
                    .buttonStyle(TapePrimaryButtonStyle())
                    .tapeRowInsets(4)
                }
            }
            .listStyle(.plain)
            .tapeScreen()
            .navigationTitle("诊断")
            .tapeNavigationChrome()
            .navigationDestination(isPresented: $showBenchmark) {
                BenchmarkView()
            }
            .task {
                refresh()
            }
        }
    }

    // MARK: - Cards

    private func signingCard(info: SigningInfo, days: Int) -> some View {
        TapeCard(fill: days <= 2 ? TapeTheme.peach : TapeTheme.card) {
            VStack(alignment: .leading, spacing: TapeTheme.space3) {
                HStack(alignment: .center, spacing: TapeTheme.space2) {
                    Image(systemName: days <= 2 ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(days <= 2 ? TapeTheme.coral : TapeTheme.ink)
                        .accessibilityHidden(true)
                    TapeSticker(
                        text: days <= 2 ? "EXPIRING" : "SIGNED",
                        fill: days <= 2 ? TapeTheme.coral : TapeTheme.acid,
                        foreground: days <= 2 ? TapeTheme.stickerInk : TapeTheme.ink,
                        angle: days <= 2 ? -4 : 4
                    )
                    Spacer(minLength: TapeTheme.space2)
                }

                Text(signingBannerText(days: days))
                    .font(TapeType.body)
                    .foregroundStyle(TapeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("signingExpiryBanner")

                Text("到期：\(info.expirationDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")")
                    .font(TapeType.monoMeta)
                    .foregroundStyle(TapeTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var benchmarkLink: some View {
        Button {
            showBenchmark = true
        } label: {
            HStack(spacing: TapeTheme.space3) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TapeTheme.ink)
                    .frame(width: 36, height: 36)
                    .background(
                        TapeTheme.acid,
                        in: RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                            .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
                    }
                Text("SwiftData 5k 基准")
                    .font(TapeType.headline)
                    .foregroundStyle(TapeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: TapeTheme.space2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TapeTheme.faint)
            }
            .padding(.horizontal, TapeTheme.space3)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(TapeTheme.card)
                    .shadow(color: TapeTheme.ink, radius: 0, x: 2, y: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
            }
        }
        .buttonStyle(TapePlainPressStyle())
        .accessibilityLabel("SwiftData 5k 基准")
        .accessibilityIdentifier("benchmarkLink")
        .tapeRowInsets(4)
    }

    private var maintenanceCard: some View {
        TapeCard {
            VStack(alignment: .leading, spacing: TapeTheme.space2) {
                if let summary = coordinator.lastCleanupSummary {
                    Group {
                        Text(summary.hasChanges ? "启动维护已完成。" : "启动维护已完成，没有需要清理的内容。")
                            .font(TapeType.body)
                            .foregroundStyle(TapeTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("maintenanceSummaryText")
                        Text("staging \(summary.stagingSessionsRemoved) · 孤儿媒体 \(summary.orphanMediaFilesRemoved) · 孤儿封面 \(summary.orphanArtworkFilesRemoved) · 缺失 \(summary.missingMarked)")
                            .font(TapeType.monoMicro)
                            .foregroundStyle(TapeTheme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("maintenanceDetailText")

                        TapeHairline()
                            .padding(.vertical, TapeTheme.space1)

                        infoRow("标记缺失", "\(summary.missingMarked)")
                        TapeHairline()
                        infoRow("恢复存在", "\(summary.restored)")
                        TapeHairline()
                        infoRow("清理孤儿媒体", "\(summary.orphanMediaFilesRemoved)")
                        TapeHairline()
                        infoRow("清理 staging", "\(summary.stagingSessionsRemoved)")
                    }

                    Group {
                        TapeHairline()
                        infoRow("清理孤儿封面", "\(summary.orphanArtworkFilesRemoved)")
                        TapeHairline()
                        infoRow("清理过期回收站", "\(summary.expiredTrashPurged)")

                        if !summary.failures.isEmpty {
                            TapeHairline()
                            ForEach(summary.failures, id: \.self) { failure in
                                Text(failure)
                                    .font(TapeType.captionSmall)
                                    .foregroundStyle(TapeTheme.coral)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                } else {
                    Text("尚未运行启动维护。")
                        .font(TapeType.body)
                        .foregroundStyle(TapeTheme.muted)
                }

                Button {
                    coordinator.runMaintenance(modelContext: modelContext)
                    refresh()
                } label: {
                    Label("立即对账 / 清理", systemImage: "cross.case")
                }
                .buttonStyle(TapePrimaryButtonStyle())
                .disabled(coordinator.isRunning)
                .opacity(coordinator.isRunning ? 0.5 : 1)
                .accessibilityIdentifier("runMaintenanceButton")
                .padding(.top, TapeTheme.space1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tapeRowInsets(6)
    }

    @ViewBuilder
    private var signingDetailCard: some View {
        TapeCard {
            VStack(alignment: .leading, spacing: TapeTheme.space2) {
                if let info = signingInfo {
                    infoRow("描述文件", info.name ?? "—")
                    TapeHairline()
                    infoRow("Team", info.teamIdentifier ?? "—")
                    TapeHairline()
                    infoRow("App ID", info.appIdentifier ?? "—")
                    if let expiration = info.expirationDate {
                        TapeHairline()
                        infoRow(
                            "到期",
                            expiration.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    if let days = info.daysRemaining {
                        TapeHairline()
                        infoRow(
                            "剩余",
                            days >= 0
                                ? L10n.format("diagnostics.daysRemaining", days)
                                : L10n.format("diagnostics.daysExpired", -days)
                        )
                    }
                    if let deviceCount = info.provisionedDeviceCount {
                        TapeHairline()
                        infoRow("描述文件设备数", "\(deviceCount)")
                    }
                    Text(info.statusText)
                        .font(TapeType.captionSmall)
                        .foregroundStyle(info.isExpired ? TapeTheme.coral : TapeTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, TapeTheme.space1)
                } else {
                    Text("未发现 embedded.mobileprovision（模拟器或未签名构建）。真机免费账号构建会显示 7 天到期时间。")
                        .font(TapeType.caption)
                        .foregroundStyle(TapeTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tapeRowInsets(6)
    }

    private func pathBlock(_ label: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: TapeTheme.space1) {
            Text(label)
                .font(TapeType.monoMicro)
                .foregroundStyle(TapeTheme.faint)
            Text(path)
                .font(TapeType.monoMeta)
                .foregroundStyle(TapeTheme.muted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Shared pieces

    private func sectionHeader(_ title: String, kicker: String) -> some View {
        TapeSectionHeader(title: title, kicker: kicker)
            .textCase(nil)
            .padding(.horizontal, TapeTheme.screenPadding)
            .padding(.top, TapeTheme.space3)
            .padding(.bottom, TapeTheme.space1)
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(TapeType.captionSmall)
            .foregroundStyle(TapeTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, TapeTheme.space4)
            .padding(.top, TapeTheme.space1)
            .listRowBackground(Color.clear)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TapeTheme.space2) {
            Text(label)
                .font(TapeType.bodySmall)
                .foregroundStyle(TapeTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: TapeTheme.space2)
            Text(value)
                .font(TapeType.monoMeta)
                .foregroundStyle(TapeTheme.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
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
