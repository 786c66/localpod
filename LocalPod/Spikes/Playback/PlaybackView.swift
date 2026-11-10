import Foundation
import SwiftUI
import SwiftData
import LocalPodKit

struct PlaybackView: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(PlaybackSession.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(
        sort: \MediaItem.addedAt,
        order: .reverse
    )
    private var allItems: [MediaItem]

    /// Set by RootView so the empty state can switch tabs.
    var onGoToLibrary: () -> Void = {}

    private var items: [MediaItem] {
        allItems.filter { $0.source != .benchmark && !$0.isMissing }
    }

    private var itemByID: [UUID: MediaItem] {
        Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
    }

    @State private var showSettings = false
    @State private var localError: String?
    @State private var scrubPosition: Double?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        playDemo(
                            name: "demo-audio",
                            fileExtension: "m4a",
                            title: "内置音频测试",
                            kind: .audio
                        )
                    } label: {
                        Label("播放内置音频", systemImage: "waveform")
                    }
                    .accessibilityIdentifier("playDemoAudioButton")

                    Button {
                        playDemo(
                            name: "demo-long-audio",
                            fileExtension: "m4a",
                            title: "内置长音频",
                            kind: .audio
                        )
                    } label: {
                        Label("播放 5 分钟测试音频", systemImage: "waveform.badge.clock")
                    }
                    .accessibilityIdentifier("playLongAudioButton")
                } header: {
                    Text("内置测试媒体")
                } footer: {
                    Text("LocalPod 只播放音频。视频文件可导入并读取其音轨，但不显示画面、不做旋转/PiP。")
                }

                Section("当前播放") {
                    playerCard
                }

                queueSection

                Section("资料库 · \(items.count)") {
                    if items.isEmpty {
                        Text("还没有可播放的条目。先在「导入」页导入演示文件夹。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { item in
                            Button {
                                playLibraryItem(item)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.kind.isVideo ? "film" : "waveform")
                                        .foregroundStyle(item.kind.isVideo ? .orange : Color.accentColor)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text("\(item.kind.displayName) · \(item.folderName ?? "资料库")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    Image(systemName: "play.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let localError {
                    Section("错误") {
                        Text(localError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("播放")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !session.queue.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("playbackSettingsButton")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    @ViewBuilder
    private var playerCard: some View {
        if let item = playback.currentItem {
            VStack(alignment: .leading, spacing: 12) {
                playerHeader(item)

                if session.sleepTimer.isActive {
                    sleepTimerStatusRow
                }

                if let error = playback.errorMessage {
                    HStack {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("重试") {
                            playback.retry()
                        }
                        .font(.caption)
                        .accessibilityIdentifier("playbackRetryButton")
                        .accessibilityHint("重新加载当前音频")
                    }
                }

                Slider(
                    value: Binding(
                        get: { scrubPosition ?? playback.currentTime },
                        set: { scrubPosition = $0 }
                    ),
                    in: 0...max(playback.duration, 1)
                ) { editing in
                    if !editing, let target = scrubPosition {
                        playback.seek(to: target)
                        scrubPosition = nil
                    }
                }
                .accessibilityIdentifier("playbackSlider")
                .accessibilityLabel("播放进度")
                .accessibilityValue(
                    "\(formatTime(scrubPosition ?? playback.currentTime))，共 \(formatTime(max(playback.duration, 0)))"
                )
                .accessibilityHint("左右滑动调整播放位置")

                HStack {
                    Text(formatTime(scrubPosition ?? playback.currentTime))
                        .accessibilityIdentifier("currentTimeText")
                    Spacer()
                    Text("-" + formatTime(max(0, playback.duration - (scrubPosition ?? playback.currentTime))))
                        .accessibilityIdentifier("remainingTimeText")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

                transportControls

                HStack(spacing: 8) {
                    Text("速度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(PlaybackPolicy.speedLabel(playback.playbackRate))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("playbackRateText")
                }

                speedChips

                sleepTimerRow
            }
            .padding(.vertical, 4)
        } else {
            ContentUnavailableView {
                Label("未在播放", systemImage: "play.circle")
                    .accessibilityIdentifier("playbackEmptyState")
            } description: {
                Text("从资料库选择条目，或播放上方的内置测试媒体。")
            } actions: {
                Button("去资料库") {
                    onGoToLibrary()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("playbackEmptyLibraryButton")
                .accessibilityHint("切换到资料库标签")
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func playerHeader(_ item: PlaybackItem) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    PlaybackArtworkView(url: item.artworkURL, kind: item.kind, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("currentPlaybackTitle")
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                }
                Text(playback.statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .accessibilityIdentifier("playbackPhaseText")
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                PlaybackArtworkView(url: item.artworkURL, kind: item.kind, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("currentPlaybackTitle")
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Text(playback.statusText)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
                    .accessibilityIdentifier("playbackPhaseText")
            }
        }
    }

    @ViewBuilder
    private var transportControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 14) {
                HStack(spacing: 24) {
                    previousButton
                    skipBackwardButton
                    skipForwardButton
                    nextButton
                }
                playPauseButton
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 24) {
                Spacer()
                previousButton
                skipBackwardButton
                playPauseButton
                skipForwardButton
                nextButton
                Spacer()
            }
        }
    }

    private var previousButton: some View {
        Button {
            session.previous()
        } label: {
            Image(systemName: "backward.end.fill")
                .font(.title2)
        }
        .accessibilityIdentifier("previousTrackButton")
        .accessibilityLabel("上一首")
        .accessibilityHint("播放队列中的上一首")
    }

    private var skipBackwardButton: some View {
        Button {
            playback.skip(by: -playback.skipBackwardInterval)
        } label: {
            Image(systemName: "gobackward")
                .font(.title2)
        }
        .accessibilityIdentifier("skipBackwardButton")
        .accessibilityLabel("快退 \(Int(playback.skipBackwardInterval)) 秒")
        .accessibilityHint("从当前位置向后跳转")
    }

    private var playPauseButton: some View {
        Button {
            playback.togglePlayPause()
        } label: {
            Image(systemName: playback.isPlaying
                ? "pause.circle.fill"
                : "play.circle.fill")
                .font(.system(size: 44))
        }
        .accessibilityIdentifier("playPauseButton")
        .accessibilityLabel(playback.isPlaying ? "暂停" : "播放")
        .accessibilityHint(playback.isPlaying ? "暂停当前音频" : "继续播放当前音频")
    }

    private var skipForwardButton: some View {
        Button {
            playback.skip(by: playback.skipForwardInterval)
        } label: {
            Image(systemName: "goforward")
                .font(.title2)
        }
        .accessibilityIdentifier("skipForwardButton")
        .accessibilityLabel("快进 \(Int(playback.skipForwardInterval)) 秒")
        .accessibilityHint("从当前位置向前跳转")
    }

    private var nextButton: some View {
        Button {
            session.next()
        } label: {
            Image(systemName: "forward.end.fill")
                .font(.title2)
        }
        .accessibilityIdentifier("nextTrackButton")
        .accessibilityLabel("下一首")
        .accessibilityHint("播放队列中的下一首")
    }

    @ViewBuilder
    private var speedChips: some View {
        ViewThatFits(in: .horizontal) {
            speedChipsRow
                .fixedSize(horizontal: true, vertical: false)
            ScrollView(.horizontal, showsIndicators: false) {
                speedChipsRow
            }
        }
    }

    private var speedChipsRow: some View {
        HStack(spacing: 8) {
            ForEach(PlaybackPolicy.featuredSpeedPresets, id: \.self) { rate in
                speedButton(rate)
            }
        }
        .padding(.vertical, 2)
    }

    private func speedButton(_ rate: Float) -> some View {
        let isSelected = playback.playbackRate == rate
        return Button {
            playback.setRate(rate)
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
        .accessibilityIdentifier("speedOption-\(rate)")
        .accessibilityLabel("速度 \(PlaybackPolicy.speedLabel(rate))")
        .accessibilityHint("把播放速度设为 \(PlaybackPolicy.speedLabel(rate))")
        .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
    }

    @ViewBuilder
    private var sleepTimerRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                skipIntervalText
                sleepTimerMenu
            }
        } else {
            HStack(spacing: 8) {
                skipIntervalText
                Spacer(minLength: 8)
                sleepTimerMenu
            }
        }
    }

    private var skipIntervalText: some View {
        Text("快进/快退 \(Int(playback.skipForwardInterval)) 秒")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sleepTimerMenu: some View {
        Menu {
            Button("关闭") {
                session.cancelSleepTimer()
            }
            ForEach([1, 5, 15, 30, 45, 60, 90], id: \.self) { minutes in
                Button("\(minutes) 分钟") {
                    session.startSleepTimer(minutes: minutes)
                }
            }
            Divider()
            Button("本集结束") {
                session.startSleepTimerEndOfEpisode()
            }
        } label: {
            Label("睡眠定时", systemImage: "moon.zzz")
                .font(.caption)
        }
        .accessibilityIdentifier("sleepTimerMenu")
        .accessibilityLabel("睡眠定时")
        .accessibilityHint("设置到点或本集结束时暂停")
    }

    private var sleepTimerStatusRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label("睡眠定时", systemImage: "moon.zzz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sleepTimerStatus)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sleepTimerStatus")
                Spacer(minLength: 4)
                Button("取消") {
                    session.cancelSleepTimer()
                }
                .font(.caption)
                .accessibilityIdentifier("sleepTimerCancelButton")
                .accessibilityHint("关闭睡眠定时")
            }
            if session.sleepTimer.mode == .endOfEpisode {
                Text("本集播完后暂停，不会自动播放下一集。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private var sleepTimerStatus: String {
        switch session.sleepTimer.mode {
        case .off:
            "关闭"
        case .minutes:
            if let remaining = session.sleepTimer.remainingText {
                "\(session.sleepTimer.mode.displayName) · \(remaining)"
            } else {
                session.sleepTimer.mode.displayName
            }
        case .endOfEpisode:
            "本集结束"
        }
    }

    private var queueSection: some View {
        Section {
            if session.queue.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("队列为空。使用「播放下一首」或「加入队列」添加条目。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("去资料库") {
                        onGoToLibrary()
                    }
                    .accessibilityIdentifier("queueEmptyLibraryButton")
                    .accessibilityHint("切换到资料库标签")
                }
            } else {
                ForEach(Array(session.queue.entries.enumerated()), id: \.element.id) { index, entry in
                    let item = itemByID[entry.itemID]
                    Button {
                        session.playQueueItem(itemID: entry.itemID)
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item?.title ?? "已删除条目")
                                    .fixedSize(horizontal: false, vertical: true)
                                if entry.itemID == session.queue.currentItemID {
                                    Text("当前")
                                        .font(.caption2)
                                        .foregroundStyle(Color.accentColor)
                                } else {
                                    Text(item?.durationText ?? "—")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if entry.itemID != session.queue.currentItemID {
                                Image(systemName: "play.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("queueRow-\(item?.title ?? entry.itemID.uuidString)")
                }
                .onMove { source, destination in
                    session.moveQueue(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) {
                        guard session.queue.entries.indices.contains(index) else { continue }
                        let entry = session.queue.entries[index]
                        session.removeQueueEntry(entryID: entry.id)
                    }
                }
            }
        } header: {
            queueHeader
        }
    }

    @ViewBuilder
    private var queueHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                queueCountTitle
                ScrollView(.horizontal, showsIndicators: false) {
                    queueActions
                }
            }
        } else {
            HStack {
                queueCountTitle
                Spacer(minLength: 8)
                queueActions
            }
        }
    }

    private var queueCountTitle: some View {
        Text("队列 · \(session.queue.count)")
            .accessibilityIdentifier("queueCountText")
            .fixedSize(horizontal: false, vertical: true)
    }

    private var queueActions: some View {
        HStack(spacing: 12) {
            Button {
                session.toggleShuffle()
            } label: {
                Label(
                    session.queue.shuffleEnabled ? "随机：开" : "随机：关",
                    systemImage: "shuffle"
                )
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(
                    session.queue.shuffleEnabled ? Color.accentColor : Color.secondary
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("queueShuffleButton")
            .accessibilityLabel("随机播放")
            .accessibilityValue(session.queue.shuffleEnabled ? "已开启" : "已关闭")
            .accessibilityHint("切换随机播放")

            Button {
                session.cycleRepeatMode()
            } label: {
                Label(
                    "循环：\(session.queue.repeatMode.displayName)",
                    systemImage: session.queue.repeatMode.symbolName
                )
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(
                    session.queue.repeatMode == .off ? Color.secondary : Color.accentColor
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("queueRepeatButton")
            .accessibilityLabel("循环模式")
            .accessibilityValue(session.queue.repeatMode.displayName)
            .accessibilityHint("切换循环模式")

            Button(role: .destructive) {
                session.clearQueue()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("queueClearButton")
            .accessibilityLabel("清空队列")
            .accessibilityHint("移除队列中的所有条目")
        }
    }

    private var statusColor: Color {
        switch playback.phase {
        case .playing, .buffering: .green
        case .failed: .red
        case .interrupted: .orange
        default: .secondary
        }
    }

    private func playDemo(name: String, fileExtension ext: String, title: String, kind: MediaKind) {
        localError = nil
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            localError = "找不到内置资源 \(name).\(ext)。"
            return
        }
        session.queue.clear()
        let item = PlaybackItem(
            title: title,
            subtitle: "内置测试媒体",
            fileURL: url,
            kind: kind
        )
        playback.load(item, autoplay: true)
    }

    private func playLibraryItem(_ item: MediaItem) {
        localError = nil
        guard item.fileURL != nil, !item.isMissing else {
            localError = "无法解析文件路径：\(item.relativePath)"
            return
        }
        session.play(item: item)
        if let error = session.lastError {
            localError = error
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct PlaybackArtworkView: View {
    let url: URL?
    let kind: MediaKind
    let size: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: kind.isVideo
                        ? [.orange.opacity(0.85), .red.opacity(0.7)]
                        : [Color.accentColor.opacity(0.85), .teal.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: kind.isVideo ? "film.fill" : "waveform")
                        .font(.system(size: size * 0.38))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = UIImage(contentsOfFile: url.path)
        }
    }
}
