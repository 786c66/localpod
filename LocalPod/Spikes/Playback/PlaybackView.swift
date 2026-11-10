import Foundation
import SwiftUI
import SwiftData
import LocalPodKit

struct PlaybackView: View {
    @Environment(PlaybackController.self) private var playback
    @Query(
        filter: #Predicate<MediaItem> { $0.sourceRaw == "import" },
        sort: \MediaItem.addedAt,
        order: .reverse
    )
    private var items: [MediaItem]

    @State private var showVideo = false
    @State private var localError: String?

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
                    Text("音频用于验证后台播放、锁屏 Now Playing 与远程控制；视频用于验证 H.264/HEVC 画面与全屏。")
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
                VideoPlayerScreen(player: playback.player)
            }
        }
    }

    @ViewBuilder
    private var playerCard: some View {
        if let item = playback.currentItem {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                            .accessibilityIdentifier("currentPlaybackTitle")
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(playback.isPlaying ? "播放中" : "已暂停")
                        .font(.caption2)
                        .foregroundStyle(playback.isPlaying ? .green : .secondary)
                }

                if let error = playback.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Slider(
                    value: Binding(
                        get: { playback.currentTime },
                        set: { playback.seek(to: $0) }
                    ),
                    in: 0...max(playback.duration, 1)
                )

                HStack {
                    Text(formatTime(playback.currentTime))
                    Spacer()
                    Text(formatTime(max(0, playback.duration - playback.currentTime)))
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
                    Spacer()
                }

                HStack {
                    Text("速度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(
                        "速度",
                        selection: Binding(
                            get: { playback.playbackRate },
                            set: { playback.setRate($0) }
                        )
                    ) {
                        Text("0.5x").tag(Float(0.5))
                        Text("1x").tag(Float(1.0))
                        Text("1.25x").tag(Float(1.25))
                        Text("1.5x").tag(Float(1.5))
                        Text("2x").tag(Float(2.0))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                if playback.isVideo {
                    Button {
                        showVideo = true
                    } label: {
                        Label("打开视频画面", systemImage: "rectangle.expand.vertical")
                    }
                }
            }
            .padding(.vertical, 4)
        } else {
            Text("未播放。选择内置测试媒体或资料库条目。")
                .foregroundStyle(.secondary)
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
            durationHint: item.durationSeconds
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
