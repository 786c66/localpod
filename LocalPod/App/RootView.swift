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
            LibraryView()
                .tabItem { Label("资料库", systemImage: "books.vertical") }
                .tag(0)

            ImportView()
                .tabItem { Label("导入", systemImage: "tray.and.arrow.down") }
                .tag(1)

            PlaybackView()
                .tabItem { Label("播放", systemImage: "play.circle") }
                .tag(2)

            InboxView()
                .tabItem { Label("收件箱", systemImage: "envelope") }
                .tag(3)

            DiagnosticsView()
                .tabItem { Label("诊断", systemImage: "stethoscope") }
                .tag(4)
        }
        .tint(.indigo)
        .task {
            importCoordinator.bootstrap(modelContext: modelContext)
            seedDebugLibraryIfNeeded()
            runLaunchAutomationIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                importCoordinator.runMaintenance(modelContext: modelContext)
                importCoordinator.importInboxIfNeeded(modelContext: modelContext)
            case .background:
                // M0/M1 policy: audio continues in the background, video pauses.
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

    /// Debug-only launch switches used by UI tests and manual simulator
    /// validation. They have no effect in Release builds.
    private func runLaunchAutomationIfNeeded() {
        #if DEBUG
        guard !didRunLaunchAutomation else { return }
        didRunLaunchAutomation = true
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("--m1-auto-acceptance-import") {
            selectedTab = 1
            importCoordinator.importAcceptanceFolder(modelContext: modelContext)
        } else if arguments.contains("--m0-auto-demo-import") {
            selectedTab = 1
            importCoordinator.importDemoFolder(modelContext: modelContext)
        }

        if arguments.contains("--m0-auto-benchmark") {
            selectedTab = 4
        }

        if arguments.contains("--m0-auto-inbox") || arguments.contains("--m1-auto-maintenance") {
            selectedTab = arguments.contains("--m0-auto-inbox") ? 3 : 4
        }

        if arguments.contains("--m1-seed-library-5000") {
            selectedTab = 0
        }

        if arguments.contains("--m0-auto-play-audio") {
            selectedTab = 2
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
            selectedTab = 2
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

    private func seedDebugLibraryIfNeeded() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--m1-seed-library-5000") else {
            return
        }
        let existing = (try? modelContext.fetchCount(FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.sourceRaw == "imported" }
        ))) ?? 0
        guard existing < 5_000 else { return }
        for index in existing..<5_000 {
            modelContext.insert(MediaItem(
                title: String(format: "压力测试条目 %05d", index + 1),
                sortTitle: String(format: "压力测试条目 %05d", index + 1),
                originalFileName: "stress-\(index).m4a",
                relativePath: "Media/stress-\(index).m4a",
                relativeFolderPath: "Season \(index / 100 + 1)",
                kind: index.isMultiple(of: 3) ? .video : .audio,
                fileExtension: index.isMultiple(of: 3) ? "mp4" : "m4a",
                byteSize: Int64(1_000 + index),
                durationSeconds: Double(index % 3_600),
                folderName: "压力测试",
                source: .imported,
                isMissing: true
            ))
        }
        try? modelContext.save()
        #endif
    }
}
