import Foundation
import SwiftUI
import SwiftData
import UIKit
import LocalPodKit

struct DiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var importedCount = 0
    @State private var benchmarkCount = 0
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
                                value: days >= 0 ? "\(days) 天" : "已过期 \(-days) 天"
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
            "LocalPod 诊断",
            "Bundle ID: \(bundleIdentifier)",
            "版本: \(appVersion)",
            "设备: \(deviceDescription)",
            "资料库: \(importedCount) 条",
            "基准: \(benchmarkCount) 条",
            "收件箱: \(inboxPath)",
            "媒体库: \(mediaPath)"
        ]
        if let info = signingInfo {
            lines.append("描述文件: \(info.name ?? "—")")
            lines.append("Team: \(info.teamIdentifier ?? "—")")
            lines.append("App ID: \(info.appIdentifier ?? "—")")
            if let expiration = info.expirationDate {
                lines.append("到期: \(expiration.formatted(date: .abbreviated, time: .shortened))")
            }
            if let days = info.daysRemaining {
                lines.append("剩余: \(days) 天")
            }
        } else {
            lines.append("描述文件: 未发现（模拟器/未签名）")
        }
        return lines.joined(separator: "\n")
    }

    private func refresh() {
        signingInfo = SigningInfo.current()
        inboxPath = ImportInbox.live.directoryURL.path
        supportPath = MediaStorage.live.applicationSupportRoot.path
        mediaPath = (try? MediaStorage.live.mediaRootURL().path) ?? "—"
        importedCount = (try? modelContext.fetchCount(
            FetchDescriptor<MediaItem>(predicate: #Predicate { $0.sourceRaw == "import" })
        )) ?? 0
        benchmarkCount = (try? modelContext.fetchCount(
            FetchDescriptor<MediaItem>(predicate: #Predicate { $0.sourceRaw == "benchmark" })
        )) ?? 0
        copied = false
    }
}
