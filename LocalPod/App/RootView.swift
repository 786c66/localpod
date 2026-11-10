import SwiftUI
import SwiftData
import LocalPodKit

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ImportCoordinator.self) private var importCoordinator
    @Environment(PlaybackController.self) private var playback

    @State private var selectedTab = 0
    @State private var autoVideoPresented = false
    @State private var didRunLaunchAutomation = false

    var body: some View {
        TabView(selection: $selectedTab) {
            ImportView()
                .tabItem { Label("导入", systemImage: "tray.and.arrow.down") }
                .tag(0)

            PlaybackView()
                .tabItem { Label("播放", systemImage: "play.circle") }
                .tag(1)

            InboxView()
                .tabItem { Label("收件箱", systemImage: "envelope") }
                .tag(2)

            BenchmarkView()
                .tabItem { Label("基准", systemImage: "gauge.with.dots.needle.67percent") }
                .tag(3)

            DiagnosticsView()
                .tabItem { Label("诊断", systemImage: "stethoscope") }
                .tag(4)
        }
        .tint(.indigo)
        .task {
            importCoordinator.bootstrap(modelContext: modelContext)
            runLaunchAutomationIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                importCoordinator.importInboxIfNeeded(modelContext: modelContext)
            case .background:
                // M0 policy: audio continues in the background, video pauses.
                if playback.isVideo {
                    playback.pause()
                }
            default:
                break
            }
        }
        .onOpenURL { url in
            importCoordinator.handleOpenURL(url, modelContext: modelContext)
        }
        .fullScreenCover(isPresented: $autoVideoPresented) {
            VideoPlayerScreen(player: playback.player)
        }
    }

    /// Debug-only launch switches used by the M0 smoke test and by manual
    /// simulator validation. They have no effect in Release builds.
    private func runLaunchAutomationIfNeeded() {
        #if DEBUG
        guard !didRunLaunchAutomation else { return }
        didRunLaunchAutomation = true
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("--m0-auto-demo-import") {
            selectedTab = 0
            importCoordinator.importDemoFolder(modelContext: modelContext)
        }

        if arguments.contains("--m0-auto-benchmark") {
            selectedTab = 3
        }

        if arguments.contains("--m0-auto-inbox") {
            selectedTab = 2
        }

        if arguments.contains("--m0-auto-play-audio") {
            selectedTab = 1
            if let url = Bundle.main.url(forResource: "demo-audio", withExtension: "m4a") {
                playback.load(
                    PlaybackItem(
                        title: "自动播放音频",
                        subtitle: "启动参数",
                        fileURL: url,
                        kind: .audio
                    ),
                    autoplay: true
                )
            }
        }

        let videoName: String?
        if arguments.contains("--m0-auto-play-h264") {
            videoName = "demo-h264"
        } else if arguments.contains("--m0-auto-play-hevc") {
            videoName = "demo-hevc"
        } else {
            videoName = nil
        }

        if let videoName,
           let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
            selectedTab = 1
            playback.load(
                PlaybackItem(
                    title: videoName,
                    subtitle: "启动参数",
                    fileURL: url,
                    kind: .video
                ),
                autoplay: true
            )
            autoVideoPresented = true
        }
        #endif
    }
}
