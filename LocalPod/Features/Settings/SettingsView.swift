import SwiftUI
import SwiftData
import LocalPodKit

struct SettingsView: View {
    @Environment(PlaybackSession.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ImportSession.startedAt, order: .reverse)
    private var importSessions: [ImportSession]

    @Query private var allItems: [MediaItem]

    @State private var maintenanceSummary: String?

    private var libraryItems: [MediaItem] {
        allItems.filter { $0.source != .benchmark }
    }

    private var totalBytes: Int64 {
        libraryItems.reduce(0) { $0 + $1.byteSize }
    }

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        @Bindable var settings = session.settings
        NavigationStack {
            Form {
                Section {
                    LabeledContent("默认倍速") {
                        Text(PlaybackPolicy.speedLabel(settings.defaultRate))
                            .accessibilityIdentifier("settingsDefaultSpeedValue")
                    }

                    ViewThatFits(in: .horizontal) {
                        speedPresetsRow(settings)
                            .fixedSize(horizontal: true, vertical: false)
                        ScrollView(.horizontal, showsIndicators: false) {
                            speedPresetsRow(settings)
                        }
                    }

                    Picker("快进间隔", selection: $settings.skipForwardSeconds) {
                        ForEach(AppSettingsStore.skipOptions, id: \.self) { seconds in
                            Text("\(Int(seconds)) 秒").tag(seconds)
                        }
                    }
                    .accessibilityIdentifier("settingsSkipForwardPicker")

                    Picker("快退间隔", selection: $settings.skipBackwardSeconds) {
                        ForEach(AppSettingsStore.skipOptions, id: \.self) { seconds in
                            Text("\(Int(seconds)) 秒").tag(seconds)
                        }
                    }
                    .accessibilityIdentifier("settingsSkipBackwardPicker")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("恢复播放位置")
                        Picker("恢复播放位置", selection: $settings.resumeEnabled) {
                            Text("记住").tag(true)
                            Text("不记住").tag(false)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settingsResumePicker")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("播完自动下一集")
                        Picker("播完自动下一集", selection: $settings.autoPlayNext) {
                            Text("自动").tag(true)
                            Text("不自动").tag(false)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settingsAutoNextPicker")
                    }
                } header: {
                    Text("播放")
                } footer: {
                    Text("所有设置立即保存，重启 App 后仍然生效。")
                }

                Section("存储") {
                    LabeledContent("资料库条目", value: "\(libraryItems.count) 条")
                    LabeledContent("占用空间", value: ByteCountFormatter.string(
                        fromByteCount: totalBytes,
                        countStyle: .file
                    ))
                    Button {
                        runMaintenance()
                    } label: {
                        Label("执行资料库维护", systemImage: "wrench.and.screwdriver")
                    }
                    .accessibilityIdentifier("settingsMaintenanceButton")
                    if let maintenanceSummary {
                        Text(maintenanceSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settingsMaintenanceSummary")
                    }
                }

                Section("导入历史") {
                    if importSessions.isEmpty {
                        Text("还没有导入记录。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(importSessions.prefix(5)) { session in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.rootName)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · 导入 \(session.importedCount) · 重复 \(session.duplicateCount) · 失败 \(session.failedCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("播放范围", value: "仅音频")
                    Text("LocalPod 只播放音频。视频文件可以导入并读取音轨，但不显示画面，也不支持旋转或画中画。完全免费，无内购、无订阅。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("settingsCloseButton")
                }
            }
            .onChange(of: settings.defaultRate) { _, _ in session.applySettings() }
            .onChange(of: settings.skipForwardSeconds) { _, _ in session.applySettings() }
            .onChange(of: settings.skipBackwardSeconds) { _, _ in session.applySettings() }
            .onChange(of: settings.resumeEnabled) { _, _ in session.applySettings() }
        }
    }

    private func speedPresetsRow(_ settings: AppSettingsStore) -> some View {
        HStack(spacing: 8) {
            ForEach(PlaybackPolicy.featuredSpeedPresets, id: \.self) { rate in
                let isSelected = settings.defaultRate == rate
                Button {
                    settings.defaultRate = rate
                } label: {
                    Text(PlaybackPolicy.speedLabel(rate))
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            isSelected
                                ? Color.accentColor.opacity(0.22)
                                : Color.secondary.opacity(0.12),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    Color.accentColor,
                                    lineWidth: isSelected ? 1.5 : 0
                                )
                        }
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settingsSpeed-\(rate)")
                .accessibilityLabel("默认速度 \(PlaybackPolicy.speedLabel(rate))")
                .accessibilityHint("把默认播放速度设为 \(PlaybackPolicy.speedLabel(rate))")
                .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
            }
        }
        .padding(.vertical, 2)
    }

    private func runMaintenance() {
        do {
            let summary = try LibraryService().reconcile(in: modelContext)
            if summary.hasChanges {
                maintenanceSummary = "缺失标记 \(summary.missingMarked) · 恢复 \(summary.restored) · 清理媒体 \(summary.orphanMediaFilesRemoved) · 清理封面 \(summary.orphanArtworkFilesRemoved)"
            } else {
                maintenanceSummary = "维护完成：没有需要清理的内容。"
            }
        } catch {
            maintenanceSummary = "维护失败：\(error.localizedDescription)"
        }
    }
}
