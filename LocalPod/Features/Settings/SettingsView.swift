import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import LocalPodKit

/// Identifiable box so the exported temp file can drive `.sheet(item:)`.
private struct ShareFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Presents the exported backup file through the system share sheet.
private struct ShareLinkSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: TapeTheme.space4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(TapeTheme.violet)
                Text(url.lastPathComponent)
                    .font(TapeType.monoMeta)
                    .foregroundStyle(TapeTheme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                ShareLink(
                    item: url,
                    preview: SharePreview(
                        url.lastPathComponent,
                        image: Image(systemName: "doc.text")
                    )
                )
                .buttonStyle(TapePrimaryButtonStyle())
                .accessibilityIdentifier("backupShareLink")
            }
            .padding(TapeTheme.space6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TapeScreenBackground())
            .navigationTitle(L10n.string("backup.export"))
            .tapeNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("backupShareDone")
                }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(PlaybackSession.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ImportCoordinator.self) private var coordinator

    @Query(sort: \ImportSession.startedAt, order: .reverse)
    private var importSessions: [ImportSession]

    @Query(sort: \LinkedFolder.addedAt, order: .reverse)
    private var linkedFolders: [LinkedFolder]

    @Query private var allItems: [MediaItem]

    @State private var maintenanceSummary: String?
    @State private var showDeleteSamplesConfirmation = false
    @State private var sampleDeleteSummary: String?
    @State private var showLinkedFolderPicker = false
    @State private var pendingRelinkFolder: LinkedFolder?
    @State private var folderPendingDelete: LinkedFolder?
    // 备份与恢复 state.
    @State private var backupExportURL: URL?
    @State private var backupExportSummary: String?
    @State private var backupRestoreSummary: String?
    @State private var showBackupImportPicker = false
    @State private var pendingRestoreDocument: BackupDocument?
    @State private var pendingRestoreFileName: String?
    // 通知 (local import notifications) state.
    @State private var importNotificationsAuthorizationDenied = false
    /// UI-test seam: ImportNotifier publishes its last decision here (DEBUG
    /// builds only). @AppStorage refreshes the row when the import finishes
    /// while Settings is already open.
    @AppStorage(ImportNotifier.debugLastDecisionDefaultsKey)
    private var lastImportNotificationText = ""
    /// Launch-argument automation (UI tests) force an immediate staleness
    /// check so the badge is visible without tapping anything first.
    @State private var didResolveStalenessOnAppear = false

    private var libraryItems: [MediaItem] {
        allItems.filter { $0.source != .benchmark }
    }

    private var sampleItems: [MediaItem] {
        allItems.filter { $0.source == .sample }
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
            List {
                playbackSection(settings)

                Section {
                    TapeCard {
                        // Keep the caption: a card whose row holds a single
                        // accessibility element gets that element's frame
                        // promoted to the whole list row (verified: 450×63 vs
                        // the switch's real 310×28), so taps aimed at the
                        // switch's trailing side miss it. A second element
                        // keeps the toggle's frame tight.
                        VStack(alignment: .leading, spacing: TapeTheme.space2) {
                            Toggle(isOn: $settings.signingReminderEnabled) {
                                Text("签名到期提醒")
                            }
                            .font(TapeType.body)
                            .foregroundStyle(TapeTheme.ink)
                            .accessibilityIdentifier("settingsSigningReminderToggle")

                            Text("描述文件到期前 2 天的 10:00 提醒你重签。")
                                .font(TapeType.captionSmall)
                                .foregroundStyle(TapeTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tapeRowInsets(6)
                } header: {
                    settingsHeader(L10n.string("签名"), kicker: "SIGNING")
                } footer: {
                    settingsFooter(L10n.string("开启后会在描述文件到期前 2 天 10:00 发送本地通知；首次开启会请求通知权限。关闭会取消待发送的提醒。若开关原本就是开启状态，请先关闭再开启一次以触发系统授权。即使拒绝通知，诊断页仍会显示到期提示。"))
                }

                storageSection

                sampleSection

                wifiSection

                linkedFoldersSection

                backupSection

                importNotificationsSection(settings)

                importHistorySection

                aboutSection
            }
            .listStyle(.plain)
            .tapeScreen()
            .navigationTitle("设置")
            .tapeNavigationChrome()
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
            .onChange(of: settings.signingReminderEnabled) { _, enabled in
                updateSigningReminder(enabled: enabled)
            }
            .onChange(of: settings.importNotificationsEnabled) { _, enabled in
                updateImportNotifications(enabled: enabled)
            }
            .alert("删除示例内容？", isPresented: $showDeleteSamplesConfirmation) {
                Button("删除", role: .destructive) {
                    deleteSamples()
                }
                .accessibilityIdentifier("sampleDeleteConfirmButton")
                Button("取消", role: .cancel) {}
            } message: {
                Text("将删除 \(sampleItems.count) 条示例及其进度、队列和播放列表引用。你导入的内容不会受影响。")
            }
            .sheet(isPresented: $showLinkedFolderPicker) {
                DocumentPicker(
                    contentTypes: [.folder],
                    onPick: { urls in
                        showLinkedFolderPicker = false
                        guard let url = urls.first else { return }
                        coordinator.linkFolder(url, modelContext: modelContext)
                    },
                    onCancel: { showLinkedFolderPicker = false }
                )
            }
            .sheet(isPresented: $showBackupImportPicker) {
                DocumentPicker(
                    contentTypes: Self.backupContentTypes,
                    onPick: { urls in
                        showBackupImportPicker = false
                        guard let url = urls.first else { return }
                        readBackupForRestore(at: url)
                    },
                    onCancel: { showBackupImportPicker = false }
                )
            }
            .sheet(
                item: Binding(
                    get: { backupExportURL.map(ShareFile.init) },
                    set: { url in backupExportURL = url?.url }
                )
            ) { file in
                ShareLinkSheet(url: file.url)
            }
            .confirmationDialog(
                L10n.string("backup.restoreConfirm.title"),
                isPresented: showRestoreConfirmation,
                titleVisibility: .visible
            ) {
                Button(L10n.string("backup.restoreConfirm.confirm"), role: .destructive) {
                    runRestore()
                }
                .accessibilityIdentifier("backupRestoreConfirm")
                Button(L10n.string("backup.restoreConfirm.cancel"), role: .cancel) {
                    pendingRestoreDocument = nil
                    pendingRestoreFileName = nil
                }
            } message: {
                Text(L10n.string("backup.restoreConfirm.message"))
            }
            .sheet(item: $pendingRelinkFolder) { folder in
                DocumentPicker(
                    contentTypes: [.folder],
                    onPick: { urls in
                        pendingRelinkFolder = nil
                        guard let url = urls.first else { return }
                        coordinator.relinkFolder(folder, newURL: url, modelContext: modelContext)
                    },
                    onCancel: { pendingRelinkFolder = nil }
                )
            }
            .confirmationDialog(
                L10n.string("linkedFolders.delete.title"),
                isPresented: showFolderDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(L10n.string("linkedFolders.delete.confirm"), role: .destructive) {
                    if let folder = folderPendingDelete {
                        coordinator.removeLinkedFolder(folder, modelContext: modelContext)
                    }
                    folderPendingDelete = nil
                }
                .accessibilityIdentifier("linkedFolderDeleteConfirmButton")
                Button(L10n.string("linkedFolders.delete.cancel"), role: .cancel) {
                    folderPendingDelete = nil
                }
            } message: {
                Text(L10n.string("linkedFolders.delete.message"))
            }
            .onAppear {
                resolveStalenessOnAppearIfNeeded()
                readBackupRestoreSummaryOnAppearIfNeeded()
            }
        }
    }

    // MARK: - Tape-styled sections

    @ViewBuilder
    private func playbackSection(_ settings: AppSettingsStore) -> some View {
        @Bindable var settings = settings
        Section {
            TapeCard {
                // Tighter than the default card rhythm: this first screen must
                // fit the signing toggle above the simulator's fold so the
                // regression can tap it without scrolling luck.
                VStack(alignment: .leading, spacing: TapeTheme.space2) {
                    HStack(alignment: .firstTextBaseline, spacing: TapeTheme.space2) {
                        Text("默认倍速")
                            .font(TapeType.body)
                            .foregroundStyle(TapeTheme.ink)
                        Spacer(minLength: TapeTheme.space2)
                        Text(PlaybackPolicy.speedLabel(settings.defaultRate))
                            .font(TapeType.monoMeta)
                            .foregroundStyle(TapeTheme.faint)
                            .accessibilityIdentifier("settingsDefaultSpeedValue")
                    }

                    ViewThatFits(in: .horizontal) {
                        speedPresetsRow(settings)
                            .fixedSize(horizontal: true, vertical: false)
                        ScrollView(.horizontal, showsIndicators: false) {
                            speedPresetsRow(settings)
                        }
                    }

                    TapeHairline()

                    Picker(selection: $settings.skipForwardSeconds) {
                        ForEach(AppSettingsStore.skipOptions, id: \.self) { seconds in
                            Text("\(Int(seconds)) 秒").tag(seconds)
                        }
                    } label: {
                        Text("快进间隔")
                            .font(TapeType.body)
                            .foregroundStyle(TapeTheme.ink)
                    }
                    .accessibilityIdentifier("settingsSkipForwardPicker")

                    TapeHairline()

                    Picker(selection: $settings.skipBackwardSeconds) {
                        ForEach(AppSettingsStore.skipOptions, id: \.self) { seconds in
                            Text("\(Int(seconds)) 秒").tag(seconds)
                        }
                    } label: {
                        Text("快退间隔")
                            .font(TapeType.body)
                            .foregroundStyle(TapeTheme.ink)
                    }
                    .accessibilityIdentifier("settingsSkipBackwardPicker")

                    TapeHairline()

                    segmentedRow(
                        title: L10n.string("恢复播放位置"),
                        selection: $settings.resumeEnabled,
                        options: [
                            (title: L10n.string("记住"), value: true),
                            (title: L10n.string("不记住"), value: false)
                        ],
                        identifier: "settingsResumePicker"
                    )

                    TapeHairline()

                    segmentedRow(
                        title: L10n.string("播完自动下一集"),
                        selection: $settings.autoPlayNext,
                        options: [
                            (title: L10n.string("自动"), value: true),
                            (title: L10n.string("不自动"), value: false)
                        ],
                        identifier: "settingsAutoNextPicker"
                    )
                }
            }
            .tapeRowInsets(6)
        } header: {
            settingsHeader(L10n.string("settings.section.playback"), kicker: "DEFAULTS")
        } footer: {
            settingsFooter(L10n.string("所有设置立即保存，重启 App 后仍然生效。"))
        }
    }

    private var storageSection: some View {
        Section {
            TapeCard {
                VStack(alignment: .leading, spacing: TapeTheme.space3) {
                    infoRow(L10n.string("资料库条目"), "\(libraryItems.count) 条")
                    TapeHairline()
                    infoRow(
                        L10n.string("占用空间"),
                        ByteCountFormatter.string(
                            fromByteCount: totalBytes,
                            countStyle: .file
                        )
                    )
                    TapeHairline()
                    Button {
                        runMaintenance()
                    } label: {
                        Label("执行资料库维护", systemImage: "wrench.and.screwdriver")
                    }
                    .buttonStyle(TapeSecondaryButtonStyle())
                    .accessibilityIdentifier("settingsMaintenanceButton")
                    if let maintenanceSummary {
                        Text(maintenanceSummary)
                            .font(TapeType.monoMicro)
                            .foregroundStyle(TapeTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("settingsMaintenanceSummary")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tapeRowInsets(6)
        } header: {
            settingsHeader(L10n.string("存储"), kicker: "STORAGE")
        }
    }

    private var wifiSection: some View {
        Section {
            TapeCard(padding: TapeTheme.space3) {
                // The kicker is also load-bearing accessibility-wise: a card
                // whose row holds a single element has that element's frame
                // promoted to the whole list cell, which stays "hittable"
                // under the navigation bar and sends taps to the bar instead
                // of the link. A second element keeps the link's frame tight,
                // so a covered row reports not-hittable and the scroll
                // continues until the card is genuinely tappable.
                VStack(alignment: .leading, spacing: TapeTheme.space2) {
                    Text("LOCAL LAN · PIN")
                        .font(TapeType.monoMicro)
                        .foregroundStyle(TapeTheme.faint)

                    NavigationLink {
                        WiFiUploadView()
                    } label: {
                        HStack(spacing: TapeTheme.space3) {
                            iconTile("wifi", fill: TapeTheme.violetSoft)
                            Text(L10n.string("wifi.title"))
                                .font(TapeType.headline)
                                .foregroundStyle(TapeTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: TapeTheme.space2)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(TapeTheme.ink)
                                .frame(width: 28, height: 28)
                                .background(TapeTheme.cream, in: Circle())
                                .overlay {
                                    Circle().strokeBorder(
                                        TapeTheme.ink,
                                        lineWidth: TapeTheme.stroke
                                    )
                                }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(TapePlainPressStyle())
                    .accessibilityIdentifier("wifiUploadLink")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tapeRowInsets(6)
        } header: {
            settingsHeader(L10n.string("settings.wifi.section"), kicker: "WI-FI")
        } footer: {
            settingsFooter(L10n.string("settings.wifi.footer"))
        }
    }

    private var importHistorySection: some View {
        Section {
            if importSessions.isEmpty {
                TapeDashedCard {
                    Text("还没有导入记录。")
                        .font(TapeType.body)
                        .foregroundStyle(TapeTheme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .tapeRowInsets(6)
            } else {
                TapeCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(importSessions.prefix(5)) { importSession in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(importSession.rootName)
                                    .font(TapeType.headline)
                                    .foregroundStyle(TapeTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(importSession.startedAt.formatted(date: .abbreviated, time: .shortened)) · 导入 \(importSession.importedCount) · 重复 \(importSession.duplicateCount) · 失败 \(importSession.failedCount)")
                                    .font(TapeType.monoMicro)
                                    .foregroundStyle(TapeTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, TapeTheme.space2)
                            if importSession.id != importSessions.prefix(5).last?.id {
                                TapeHairline()
                            }
                        }
                    }
                }
                .tapeRowInsets(6)
            }
        } header: {
            settingsHeader(L10n.string("导入历史"), kicker: "IMPORT LOG")
        }
    }

    private var aboutSection: some View {
        Section {
            TapeCard {
                VStack(alignment: .leading, spacing: TapeTheme.space3) {
                    infoRow(L10n.string("版本"), appVersion)
                    TapeHairline()
                    infoRow(L10n.string("播放范围"), L10n.string("settings.audioOnly"))
                    TapeHairline()
                    Text("LocalPod 只播放音频。视频文件可以导入并读取音轨，但不显示画面，也不支持旋转或画中画。完全免费，无内购、无订阅。")
                        .font(TapeType.captionSmall)
                        .foregroundStyle(TapeTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tapeRowInsets(6)
        } header: {
            settingsHeader(L10n.string("关于"), kicker: "ABOUT")
        }
    }

    // MARK: - Section chrome

    private func settingsHeaderBase(_ title: String, _ kicker: String) -> some View {
        TapeSectionHeader(title: title, kicker: kicker)
            .textCase(nil)
            .padding(.horizontal, TapeTheme.screenPadding)
            .padding(.top, TapeTheme.space3)
            .padding(.bottom, TapeTheme.space1)
    }

    @ViewBuilder
    private func settingsHeader(
        _ title: String,
        kicker: String,
        identifier: String? = nil
    ) -> some View {
        if let identifier {
            settingsHeaderBase(title, kicker)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(identifier)
        } else {
            settingsHeaderBase(title, kicker)
        }
    }

    private func settingsFooter(_ text: String) -> some View {
        Text(text)
            .font(TapeType.captionSmall)
            .foregroundStyle(TapeTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TapeTheme.space4)
            .padding(.top, TapeTheme.space1)
            .listRowBackground(Color.clear)
    }

    // MARK: - Small pieces

    private func segmentedRow(
        title: String,
        selection: Binding<Bool>,
        options: [(title: String, value: Bool)],
        identifier: String
    ) -> some View {
        // Title and control share one row: two stacked segmented pickers were
        // ~60pt taller and pushed the signing card below the simulator
        // viewport, which broke the reminder-toggle regression.
        VStack(alignment: .leading, spacing: TapeTheme.space2) {
            HStack(alignment: .center, spacing: TapeTheme.space2) {
                Text(title)
                    .font(TapeType.body)
                    .foregroundStyle(TapeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: TapeTheme.space2)
                Picker(title, selection: selection) {
                    ForEach(options.indices, id: \.self) { index in
                        Text(options[index].title).tag(options[index].value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier(identifier)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TapeTheme.space2) {
            Text(label)
                .font(TapeType.body)
                .foregroundStyle(TapeTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: TapeTheme.space2)
            Text(value)
                .font(TapeType.monoMeta)
                .foregroundStyle(TapeTheme.faint)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func iconTile(_ icon: String, fill: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                .fill(fill)
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TapeTheme.ink)
        }
        .frame(width: 36, height: 36)
        .overlay {
            RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
        }
        .accessibilityHidden(true)
    }

    /// UI-test/launch automation hook: `--p2-check-stale-linked-folders`
    /// resolves every bookmark once when the settings page appears and flags
    /// rows whose folder is gone. Deliberately not part of normal launches:
    /// resolving all bookmarks on every settings visit would wake up iCloud
    /// placeholders for rows the user has not touched.
    private func resolveStalenessOnAppearIfNeeded() {
        #if DEBUG
        guard !didResolveStalenessOnAppear,
              ProcessInfo.processInfo.arguments.contains("--p2-check-stale-linked-folders") else {
            return
        }
        didResolveStalenessOnAppear = true
        for folder in linkedFolders {
            guard !folder.isStale else { continue }
            if case .failure = LinkedFolderStore.resolve(folder.bookmarkData) {
                LinkedFolderStore.markStale(folder)
            }
        }
        try? modelContext.save()
        #endif
    }

    /// UI-test/launch automation hook: `--p2-import-backup` restores the debug
    /// backup at bootstrap, before any Settings view exists, and publishes the
    /// restore summary through UserDefaults. Surfacing it here shows the real
    /// bootstrap-restore result in the section where a manual restore's
    /// summary would appear. DEBUG-only and harmless on normal launches (the
    /// key is only ever written by the import seam).
    private func readBackupRestoreSummaryOnAppearIfNeeded() {
        #if DEBUG
        guard backupRestoreSummary == nil,
              let summary = UserDefaults.standard.string(
                  forKey: P2DebugSeed.restoreSummaryDefaultsKey
              ) else {
            return
        }
        backupRestoreSummary = summary
        #endif
    }

    /// 链接的文件夹: rows for each linked source folder plus the add/sync
    /// actions. All state lives in the coordinator/model; this view never
    /// touches bookmarks directly. Placed in Settings (not ImportView) on
    /// purpose — see the P1 regression note about top-of-ImportView UI.
    @ViewBuilder
    private var linkedFoldersSection: some View {
        Section {
            TapeCard {
                VStack(alignment: .leading, spacing: TapeTheme.space3) {
                    ForEach(linkedFolders) { folder in
                        linkedFolderRow(folder)
                        if folder.id != linkedFolders.last?.id {
                            TapeHairline()
                        }
                    }

                    if !linkedFolders.isEmpty {
                        TapeHairline()
                    }

                    Button {
                        showLinkedFolderPicker = true
                    } label: {
                        Label(
                            L10n.string("linkedFolders.add"),
                            systemImage: "link.badge.plus"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TapePrimaryButtonStyle())
                    .disabled(coordinator.isRunning)
                    .opacity(coordinator.isRunning ? 0.5 : 1)
                    .accessibilityIdentifier("linkedFolderAddButton")

                    if !linkedFolders.isEmpty {
                        Text(L10n.string("linkedFolders.hint"))
                            .font(TapeType.captionSmall)
                            .foregroundStyle(TapeTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("linkedFolderHintText")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tapeRowInsets(6)
        } header: {
            settingsHeader(
                L10n.string("linkedFolders.section"),
                kicker: "FOLDERS",
                identifier: "linkedFoldersSection"
            )
        } footer: {
            if linkedFolders.isEmpty {
                settingsFooter(L10n.string("linkedFolders.emptyFooter"))
            }
        }
    }

    /// 备份与恢复: data-only JSON export via the share sheet, and restore
    /// (merge into the current library) via the document picker. Placed after
    /// the linked-folders section, per the regression rule that new UI is
    /// appended after existing content and existing sections never reorder.
    @ViewBuilder
    private var backupSection: some View {
        Section {
            TapeCard {
                VStack(alignment: .leading, spacing: TapeTheme.space3) {
                    Button {
                        runExportBackup()
                    } label: {
                        Label(
                            L10n.string("backup.export"),
                            systemImage: "square.and.arrow.up"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TapePrimaryButtonStyle())
                    .accessibilityIdentifier("backupExportButton")

                    if let backupExportSummary {
                        Text(backupExportSummary)
                            .font(TapeType.monoMicro)
                            .foregroundStyle(TapeTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("backupExportSummary")
                    }

                    TapeHairline()

                    Button {
                        showBackupImportPicker = true
                    } label: {
                        Label(
                            L10n.string("backup.import"),
                            systemImage: "square.and.arrow.down"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TapeSecondaryButtonStyle())
                    .accessibilityIdentifier("backupImportButton")

                    if let backupRestoreSummary {
                        Text(backupRestoreSummary)
                            .font(TapeType.monoMicro)
                            .foregroundStyle(TapeTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("backupRestoreSummary")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tapeRowInsets(6)
        } header: {
            settingsHeader(
                L10n.string("backup.section"),
                kicker: "BACKUP",
                identifier: "backupSection"
            )
        } footer: {
            settingsFooter(L10n.string("backup.footer"))
        }
    }

    /// 通知: local import finished/failed notifications. Appended after the
    /// backup section and before 导入历史, per the P1 regression rule that new
    /// settings UI never reorders existing sections.
    @ViewBuilder
    private func importNotificationsSection(_ settings: AppSettingsStore) -> some View {
        @Bindable var settings = settings
        Section {
            TapeCard {
                VStack(alignment: .leading, spacing: TapeTheme.space2) {
                    Toggle(isOn: $settings.importNotificationsEnabled) {
                        Text(L10n.string("settings.notifications.toggle"))
                    }
                    .font(TapeType.body)
                    .foregroundStyle(TapeTheme.ink)
                    .accessibilityIdentifier("importNotificationsToggle")

                    if importNotificationsAuthorizationDenied {
                        Text(L10n.string("settings.notifications.denied"))
                            .font(TapeType.captionSmall)
                            .foregroundStyle(TapeTheme.coral)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("importNotificationsDeniedHint")
                    }

                    #if DEBUG
                    if !lastImportNotificationText.isEmpty {
                        Text(lastImportNotificationText)
                            .font(TapeType.monoMicro)
                            .foregroundStyle(TapeTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("lastImportNotificationText")
                    }
                    #endif
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tapeRowInsets(6)
        } header: {
            settingsHeader(
                L10n.string("settings.notifications.section"),
                kicker: "NOTIFICATIONS",
                identifier: "importNotificationsSection"
            )
        } footer: {
            settingsFooter(L10n.string("settings.notifications.footer"))
        }
    }

    private func updateImportNotifications(enabled: Bool) {
        // Turning it off never needs system authorization; the didSet already
        // persisted the value.
        guard enabled else { return }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--p2-enable-import-notifications") {
            // The UI suite turns the setting on at launch; never prompt there.
            return
        }
        #endif

        Task {
            let granted = await ImportNotifier.requestAuthorization()
            if granted {
                importNotificationsAuthorizationDenied = false
            } else {
                // Revert the toggle so the UI never claims notifications work
                // when the system will drop them, and explain the fix.
                session.settings.importNotificationsEnabled = false
                importNotificationsAuthorizationDenied = true
            }
        }
    }

    /// Export: snapshot → JSON temp file → share sheet. Fast on the main
    /// actor (a full library snapshot is a few hundred small row reads);
    /// matching how Settings runs maintenance synchronously.
    private func runExportBackup() {
        do {
            let document = try BackupService().snapshot(
                in: modelContext,
                settings: session.settings
            )
            let url = try BackupService.exportURL(document)
            backupExportURL = url
            backupExportSummary = L10n.format(
                "backup.exportSummary",
                document.items.count,
                document.playlists.count,
                document.playbackStates.count
            )
        } catch {
            backupExportSummary = L10n.format(
                "backup.exportFailed",
                error.localizedDescription
            )
        }
    }

    /// Import step 1: read and validate the picked file. Security-scoped
    /// access is handled inside `BackupService.readDocument`. A valid
    /// document is parked and only restored after the user confirms the
    /// merge warning dialog.
    private func readBackupForRestore(at url: URL) {
        do {
            let document = try BackupService.readDocument(from: url)
            pendingRestoreDocument = document
            pendingRestoreFileName = url.lastPathComponent
        } catch {
            backupRestoreSummary = L10n.format(
                "backup.importFailed",
                error.localizedDescription
            )
        }
    }

    private var showRestoreConfirmation: Binding<Bool> {
        Binding(
            get: { pendingRestoreDocument != nil },
            set: { shown in
                if !shown {
                    pendingRestoreDocument = nil
                    pendingRestoreFileName = nil
                }
            }
        )
    }

    /// Import step 2: the confirmed restore. SwiftData work stays on the
    /// main actor (same as LibraryService/TrashService paths); the decode
    /// already happened in the picker callback.
    private func runRestore() {
        guard let document = pendingRestoreDocument else { return }
        pendingRestoreDocument = nil
        do {
            let result = try BackupService().restore(
                document,
                into: modelContext,
                settings: session.settings
            )
            backupRestoreSummary = L10n.format(
                "backup.restoreSummary",
                result.itemsRestored,
                result.itemsMatched,
                result.itemsMissingMedia,
                result.playlistsCreated,
                result.playlistsMerged,
                result.progressUpdated
            )
        } catch {
            backupRestoreSummary = L10n.format(
                "backup.importFailed",
                error.localizedDescription
            )
        }
    }

    /// The picker's `.json` fallback: `UTType.json` exists on iOS 14+, but
    /// files picked from some providers lose the extension-based typing, so
    /// plain `public.json` (what `UTType.json` maps to) is the primary and
    /// only entry here — matching the single-type folder picker convention.
    private static var backupContentTypes: [UTType] {
        [.json]
    }

    @ViewBuilder
    private func linkedFolderRow(_ folder: LinkedFolder) -> some View {
        VStack(alignment: .leading, spacing: TapeTheme.space2) {
            HStack(alignment: .center, spacing: TapeTheme.space2) {
                Text(folder.rootName)
                    .font(TapeType.headline)
                    .foregroundStyle(TapeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("linkedFolderName-\(folder.rootName)")
                Spacer(minLength: TapeTheme.space2)
                if folder.isStale {
                    TapeSticker(
                        text: L10n.string("linkedFolders.staleBadge"),
                        fill: TapeTheme.coral,
                        angle: -4
                    )
                    .accessibilityIdentifier("linkedFolderStaleBadge")
                }
            }

            Text(lastScannedText(folder))
                .font(TapeType.monoMicro)
                .foregroundStyle(TapeTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("linkedFolderSyncSummary-\(folder.rootName)")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: TapeTheme.space4) {
                    folderActionButton(folder)
                    removeFolderButton(folder)
                }
                VStack(alignment: .leading, spacing: TapeTheme.space1) {
                    folderActionButton(folder)
                    removeFolderButton(folder)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func folderActionButton(_ folder: LinkedFolder) -> some View {
        if folder.isStale {
            Button {
                pendingRelinkFolder = folder
            } label: {
                Label(
                    L10n.string("linkedFolders.relink"),
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(TapeType.bodySmall)
                .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(TapePlainPressStyle())
            .foregroundStyle(TapeTheme.violet)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .disabled(coordinator.isRunning)
            .accessibilityIdentifier("linkedFolderRelinkButton")
        } else {
            Button {
                coordinator.rescanLinkedFolder(folder, modelContext: modelContext)
            } label: {
                Label(
                    L10n.string("linkedFolders.syncNow"),
                    systemImage: "arrow.clockwise"
                )
                .font(TapeType.bodySmall)
                .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(TapePlainPressStyle())
            .foregroundStyle(TapeTheme.violet)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .disabled(coordinator.isRunning)
            .accessibilityIdentifier(syncButtonIdentifier(folder))
        }
    }

    private func removeFolderButton(_ folder: LinkedFolder) -> some View {
        Button(role: .destructive) {
            folderPendingDelete = folder
        } label: {
            Label(L10n.string("linkedFolders.remove"), systemImage: "trash")
                .font(TapeType.bodySmall)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(TapePlainPressStyle())
        .foregroundStyle(TapeTheme.coral)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityIdentifier("linkedFolderRemoveButton")
    }

    private func lastScannedText(_ folder: LinkedFolder) -> String {
        guard let scannedAt = folder.lastScannedAt else {
            return L10n.string("linkedFolders.neverSynced")
        }
        let date = scannedAt.formatted(date: .abbreviated, time: .shortened)
        return L10n.format(
            "linkedFolders.lastScan",
            date,
            folder.lastImportedCount,
            folder.lastRemovedCount
        )
    }

    /// Stable single id while only one folder is linked; suffixed when several
    /// exist so UI tests can still target a specific row.
    private func syncButtonIdentifier(_ folder: LinkedFolder) -> String {
        linkedFolders.count <= 1
            ? "linkedFolderSync"
            : "linkedFolderSync-\(folder.rootName)"
    }

    /// confirmationDialog needs a concrete Bool binding; `folderPendingDelete`
    /// is optional, so project it.
    private var showFolderDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { folderPendingDelete != nil },
            set: { shown in
                if !shown { folderPendingDelete = nil }
            }
        )
    }

    @ViewBuilder
    private var sampleSection: some View {
        Section {
            TapeCard {
                VStack(alignment: .leading, spacing: TapeTheme.space3) {
                    HStack(alignment: .firstTextBaseline, spacing: TapeTheme.space2) {
                        Text("示例条目")
                            .font(TapeType.body)
                            .foregroundStyle(TapeTheme.ink)
                        Spacer(minLength: TapeTheme.space2)
                        Text("\(sampleItems.count) 条")
                            .font(TapeType.monoMeta)
                            .foregroundStyle(TapeTheme.faint)
                            .accessibilityIdentifier("sampleCountText")
                    }

                    Button(role: .destructive) {
                        showDeleteSamplesConfirmation = true
                    } label: {
                        Label("删除示例内容", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TapeDestructiveButtonStyle())
                    .disabled(sampleItems.isEmpty)
                    .opacity(sampleItems.isEmpty ? 0.5 : 1)
                    .accessibilityIdentifier("sampleDeleteButton")

                    if let sampleDeleteSummary {
                        Text(sampleDeleteSummary)
                            .font(TapeType.monoMicro)
                            .foregroundStyle(TapeTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("sampleDeleteSummary")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tapeRowInsets(6)
        } header: {
            settingsHeader(L10n.string("示例内容"), kicker: "SAMPLES")
        } footer: {
            settingsFooter(L10n.string("内置示例均为自生成的系统语音，不包含第三方内容。删除会同时移除示例的进度、队列与播放列表引用；之后可以重新添加。"))
        }
    }

    private func speedPresetsRow(_ settings: AppSettingsStore) -> some View {
        HStack(spacing: TapeTheme.space2) {
            ForEach(PlaybackPolicy.featuredSpeedPresets, id: \.self) { rate in
                let isSelected = settings.defaultRate == rate
                TapeChip(
                    text: PlaybackPolicy.speedLabel(rate),
                    isSelected: isSelected
                ) {
                    settings.defaultRate = rate
                }
                .accessibilityIdentifier("settingsSpeed-\(rate)")
                .accessibilityLabel("默认速度 \(PlaybackPolicy.speedLabel(rate))")
                .accessibilityHint("把默认播放速度设为 \(PlaybackPolicy.speedLabel(rate))")
                .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
            }
        }
        .padding(.vertical, 2)
    }

    private func updateSigningReminder(enabled: Bool) {
        let expirationDate = SigningInfo.current()?.expirationDate
        Task {
            await SigningReminder.setEnabled(
                enabled,
                expirationDate: expirationDate
            )
        }
    }

    private func runMaintenance() {
        do {
            let summary = try LibraryService().reconcile(in: modelContext)
            if summary.hasChanges {
                maintenanceSummary = L10n.format(
                    "settings.maintenance.changed",
                    summary.missingMarked,
                    summary.restored,
                    summary.orphanMediaFilesRemoved,
                    summary.orphanArtworkFilesRemoved
                )
            } else {
                maintenanceSummary = L10n.string("settings.maintenance.clean")
            }
        } catch {
            maintenanceSummary = L10n.format(
                "settings.maintenance.failed",
                error.localizedDescription
            )
        }
    }

    private func deleteSamples() {
        let sampleIDs = sampleItems.map(\.id)
        do {
            let result = try LibraryService().deleteSamples(in: modelContext)
            // The persisted queue was cleaned by LibraryService; keep the
            // in-memory session consistent too, especially if a sample is the
            // currently loaded item.
            for id in sampleIDs {
                session.handleDeletedItem(id)
            }
            let freed = ByteCountFormatter.string(
                fromByteCount: result.freedBytes,
                countStyle: .file
            )
            sampleDeleteSummary = L10n.format(
                "settings.samples.deleted",
                result.deletedCount,
                freed,
                result.removedPlaybackStates,
                result.removedQueueEntries,
                result.removedPlaylistEntries,
                result.removedMediaFiles,
                result.removedArtworkFiles
            )
        } catch {
            sampleDeleteSummary = L10n.format(
                "settings.samples.deleteFailed",
                error.localizedDescription
            )
        }
    }
}
