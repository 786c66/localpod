import Foundation
import SwiftUI
import SwiftData
import LocalPodKit

struct PlaybackView: View {
    @Environment(PlaybackController.self) private var playback
    @Query(
        sort: \MediaItem.addedAt,
        order: .reverse
    )
    private var allItems: [MediaItem]

    private var items: [MediaItem] {
        allItems.filter { $0.source != .benchmark && !$0.isMissing }
    }

    @State private var showVideo = false
    @State private var localError: String?
    @State private var scrubPosition: Double?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        playDemo(name: "demo-audio", fileExtension: "m4a", title: "内置音频测试", kind: .audio)
                    } label: {
                        Label("播放内置音频", systemImage: "waveform")
                    }
                    .accessibilityIdentifier("playDemoAudioButton")

                    Button {
                        playDemo(name: "demo-long-audio", fileExtension: "m4a", title: "内置长音频", kind: .audio)
                    } label: {
                        Label("播放 5 分钟测试音频", systemImage: "waveform.badge.clock")
                    }
                    .accessibilityIdentifier("playLongAudioButton")

                    Button {
                        playDemo(name: "demo-h264", fileExtension: "mp4", title: "内置 H.264 视频", kind: .video)
                    } label: {
                        Label("播放 H.264 视频", systemImage: "film")
                    }
                    .accessibilityIdentifier("playH264Button")

                    Button {
                        playDemo(name: "demo-hevc", fileExtension: "mp4", title: "内置 HEVC 视频", kind: .video)
                    } label: {
                        Label("播放 HEVC 视频", systemImage: "film.stack")
                    }
                    .accessibilityIdentifier("playHEVCButton")
                } header: {
                    Text("内置测试媒体")
                } footer: {
                    Text("音频用于验证后台播放、进度恢复、倍速与锁屏 Now Playing；视频用于验证画面、全屏、PiP 与 AirPlay。")
                }

                Section("当前播放") {
                    playerCard
                }

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
            .fullScreenCover(isPresented: $showVideo) {
                VideoPlayerScreen(
                    player: playback.player,
                    onPictureInPictureChange: { playback.setPictureInPictureActive($0) },
                    onRestoreUI: { showVideo = true }
                )
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

                HStack(spacing: 32) {
                    Spacer()
                    Button {
                        playback.skip(by: -15)
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title2)
                    }
                    .accessibilityIdentifier("skipBackwardButton")
                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                    }
                    .accessibilityIdentifier("playPauseButton")
                    Button {
                        playback.skip(by: 15)
                    } label: {
                        Image(systemName: "goforward.15")
                            .font(.title2)
                    }
                    .accessibilityIdentifier("skipForwardButton")
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

                if playback.isVideo {
                    Button {
                        showVideo = true
                    } label: {
                        Label("打开视频画面", systemImage: "rectangle.expand.vertical")
                    }
                    .accessibilityIdentifier("openVideoButton")
                }
            }
            .padding(.vertical, 4)
        } else {
            Text("未播放。选择内置测试媒体或资料库条目。")
                .foregroundStyle(.secondary)
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
        let item = PlaybackItem(
            title: title,
            subtitle: "内置测试媒体",
            fileURL: url,
            kind: kind
        )
        playback.load(item, autoplay: true)
        if kind.isVideo {
            showVideo = true
        }
    }

    private func playLibraryItem(_ item: MediaItem) {
        localError = nil
        guard let url = item.fileURL else {
            localError = "无法解析文件路径：\(item.relativePath)"
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            localError = "文件不存在：\(url.lastPathComponent)"
            return
        }
        let playbackItem = PlaybackItem(
            title: item.title,
            subtitle: item.folderName ?? "资料库",
            fileURL: url,
            kind: item.kind,
            durationHint: item.durationSeconds,
            libraryItemID: item.id,
            artworkURL: item.artworkURL
        )
        playback.load(playbackItem, autoplay: true)
        if item.kind.isVideo {
            showVideo = true
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
