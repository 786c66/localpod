import Foundation
import SwiftUI
import SwiftData
import LocalPodKit

struct PlaybackView: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(PlaybackSession.self) private var session
    @Query(
        sort: \MediaItem.addedAt,
        order: .reverse
    )
    private var allItems: [MediaItem]

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

                if session.sleepTimer.isActive {
                    sleepTimerSection
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
                                        .foregroundStyle(item.kind.isVideo ? .orange : .indigo)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .lineLimit(1)
                                        Text("\(item.kind.displayName) · \(item.folderName ?? "资料库")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    PlaybackArtworkView(url: item.artworkURL, kind: item.kind, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                            .accessibilityIdentifier("currentPlaybackTitle")
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(playback.statusText)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                        .accessibilityIdentifier("playbackPhaseText")
                }

                if let error = playback.errorMessage {
                    HStack {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Button("重试") {
                            playback.retry()
                        }
                        .font(.caption)
                        .accessibilityIdentifier("playbackRetryButton")
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

                HStack {
                    Text(formatTime(scrubPosition ?? playback.currentTime))
                        .accessibilityIdentifier("currentTimeText")
                    Spacer()
                    Text("-" + formatTime(max(0, playback.duration - (scrubPosition ?? playback.currentTime))))
                        .accessibilityIdentifier("remainingTimeText")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

                HStack(spacing: 24) {
                    Spacer()
                    Button {
                        session.previous()
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.title2)
                    }
                    .accessibilityIdentifier("previousTrackButton")

                    Button {
                        playback.skip(by: -playback.skipBackwardInterval)
                    } label: {
                        Image(systemName: "gobackward")
                            .font(.title2)
                    }
                    .accessibilityIdentifier("skipBackwardButton")

                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Image(systemName: playback.isPlaying
                            ? "pause.circle.fill"
                            : "play.circle.fill")
                            .font(.system(size: 44))
                    }
                    .accessibilityIdentifier("playPauseButton")

                    Button {
                        playback.skip(by: playback.skipForwardInterval)
                    } label: {
                        Image(systemName: "goforward")
                            .font(.title2)
                    }
                    .accessibilityIdentifier("skipForwardButton")

                    Button {
                        session.next()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.title2)
                    }
                    .accessibilityIdentifier("nextTrackButton")
                    Spacer()
                }

                HStack(spacing: 8) {
                    Text("速度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(PlaybackPolicy.speedLabel(playback.playbackRate))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("playbackRateText")
                }

                HStack(spacing: 8) {
                    ForEach(PlaybackPolicy.featuredSpeedPresets, id: \.self) { rate in
                        Button {
                            playback.setRate(rate)
                        } label: {
                            Text(PlaybackPolicy.speedLabel(rate))
                                .font(.caption.weight(
                                    playback.playbackRate == rate ? .semibold : .regular
                                ))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    playback.playbackRate == rate
                                        ? Color.indigo
                                        : Color.secondary.opacity(0.12),
                                    in: Capsule()
                                )
                                .foregroundStyle(
                                    playback.playbackRate == rate ? .white : .primary
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("speedOption-\(rate)")
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Text("快进/快退 \(Int(playback.skipForwardInterval)) 秒")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
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
                }
            }
            .padding(.vertical, 4)
        } else {
            Text("未播放。选择内置测试媒体、资料库条目或队列。")
                .foregroundStyle(.secondary)
        }
    }

    private var sleepTimerSection: some View {
        Section("睡眠定时") {
            LabeledContent("模式") {
                Text(sleepTimerStatus)
                    .accessibilityIdentifier("sleepTimerStatus")
            }
            if session.sleepTimer.mode == .endOfEpisode {
                Text("本集播完后暂停，不会自动播放下一集。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("取消睡眠定时", role: .destructive) {
                session.cancelSleepTimer()
            }
            .accessibilityIdentifier("sleepTimerCancelButton")
        }
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
                Text("队列为空。使用「播放下一首」或「加入队列」添加条目。")
                    .foregroundStyle(.secondary)
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
                                    .lineLimit(1)
                                if entry.itemID == session.queue.currentItemID {
                                    Text("当前")
                                        .font(.caption2)
                                        .foregroundStyle(.indigo)
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
            HStack {
                Text("队列 · \(session.queue.count)")
                    .accessibilityIdentifier("queueCountText")
                Spacer()
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
                        session.queue.shuffleEnabled ? Color.indigo : Color.secondary
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("queueShuffleButton")

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
                        session.queue.repeatMode == .off ? Color.secondary : Color.indigo
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("queueRepeatButton")

                Button(role: .destructive) {
                    session.clearQueue()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("queueClearButton")
            }
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
                        : [.indigo.opacity(0.85), .teal.opacity(0.7)],
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
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = UIImage(contentsOfFile: url.path)
        }
    }
}
