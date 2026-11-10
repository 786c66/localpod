import SwiftUI
import SwiftData
import LocalPodKit

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ImportCoordinator.self) private var importCoordinator
    @Environment(PlaybackController.self) private var playback
    @Environment(PlaybackSession.self) private var session

    @AppStorage(OnboardingStorage.completedKey) private var onboardingCompleted = false

    @State private var selectedTab = 0
    @State private var showSettings = false
    @State private var showOnboarding = false
    @State private var didResolveOnboarding = false
    @State private var didRunLaunchAutomation = false

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem { Label("资料库", systemImage: "books.vertical") }
                .tag(0)

            ImportView()
                .tabItem { Label("导入", systemImage: "tray.and.arrow.down") }
                .tag(1)

            PlaybackView(onGoToLibrary: { selectedTab = 0 })
                .tabItem { Label(L10n.string("tab.playback"), systemImage: "play.circle") }
                .tag(2)

            InboxView()
                .tabItem { Label("收件箱", systemImage: "envelope") }
                .tag(3)

            DiagnosticsView()
                .tabItem { Label("诊断", systemImage: "stethoscope") }
                .tag(4)
        }
        .tint(Color.accentColor)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(
                onContinue: { finishOnboarding() },
                onGoToImport: { finishOnboarding(selectingTab: 1) },
                onSkip: { finishOnboarding() }
            )
            // A swipe-down dismissal is still a completed first run; do not
            // nag on every launch.
            .onDisappear { onboardingCompleted = true }
        }
        .task {
            session.attach(
                context: modelContext,
                progressStore: PlaybackProgressStore(context: modelContext)
            )
            importCoordinator.bootstrap(modelContext: modelContext)
            seedDebugLibraryIfNeeded()
            seedM3FixturesIfNeeded()
            runLaunchAutomationIfNeeded()
            resolveOnboardingIfNeeded()
            // Local-only expiry reminder. This never prompts at launch: it
            // skips silently until the user enables notifications in Settings.
            await SigningReminder.refresh(
                expirationDate: SigningInfo.current()?.expirationDate,
                isEnabled: session.settings.signingReminderEnabled
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                importCoordinator.runMaintenance(modelContext: modelContext)
                importCoordinator.importInboxIfNeeded(modelContext: modelContext)
            case .background:
                // Audio continues in the background; only force a progress save.
                playback.handleSceneDidEnterBackground()
            default:
                break
            }
        }
        .task(id: scenePhase) {
            // Foreground inbox watcher: a Finder copy can finish while the app is
            // already active, so scan periodically in addition to launch/active.
            // The coordinator de-duplicates overlapping observations and imports
            // only files whose size has stopped changing.
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                importCoordinator.importInboxIfNeeded(modelContext: modelContext)
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onOpenURL { url in
            importCoordinator.handleOpenURL(url, modelContext: modelContext)
        }
        // Normal builds follow the system appearance. The iOS 27.1 simulator
        // used by UI tests does not propagate XCUIDevice.appearance into the
        // AUT, so a DEBUG-only launch switch lets M5 capture a real dark-mode
        // screenshot through SwiftUI's color scheme.
        .preferredColorScheme(debugColorSchemeOverride)
    }

    private var debugColorSchemeOverride: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--m5-force-dark-appearance") {
            return .dark
        }
        #endif
        return nil
    }

    /// Stable identity for the debug long-audio clip so progress resume can be
    /// exercised across app launches in UI tests.
    private static let m2LongAudioLibraryID =
        UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    private func resolveOnboardingIfNeeded() {
        guard !didResolveOnboarding else { return }
        didResolveOnboarding = true

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--m5-show-onboarding") {
            showOnboarding = true
            return
        }
        if arguments.contains("--m5-skip-onboarding") {
            return
        }
        #endif

        showOnboarding = !onboardingCompleted
    }

    private func finishOnboarding(selectingTab tab: Int? = nil) {
        onboardingCompleted = true
        showOnboarding = false
        if let tab {
            selectedTab = tab
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
                        title: L10n.string("playback.demo.autoTitle"),
                        subtitle: L10n.string("playback.demo.launchArgumentSubtitle"),
                        fileURL: url,
                        kind: .audio
                    ),
                    autoplay: true
                )
            }
        }

        if arguments.contains("--m3-open-settings") {
            showSettings = true
        }

        if arguments.contains("--m3-arm-end-of-episode") {
            // Arm before playback so the 20s fixture cannot end while the
            // sleep-timer menu is still opening in UI tests.
            session.startSleepTimerEndOfEpisode()
        }

        if arguments.contains("--m3-no-auto-next") {
            // Queue UI tests navigate for over a minute; with a 20s fixture
            // auto-next would advance the current item before the test
            // deletes it. Disable auto-next so the queue stays deterministic.
            session.settings.autoPlayNext = false
        }

        if arguments.contains("--m3-auto-play-first") {
            selectedTab = 2
            session.playQueueItem(
                itemID: session.queue.currentItemID ?? M3DebugSeed.itemA
            )
        }

        if arguments.contains("--m2-auto-play-long-audio") {
            selectedTab = 2
            if let url = Bundle.main.url(
                forResource: "demo-long-audio",
                withExtension: "m4a"
            ) {
                playback.load(
                    PlaybackItem(
                        title: L10n.string("playback.demo.longAudioTitle"),
                        subtitle: L10n.string("playback.demo.launchArgumentSubtitle"),
                        fileURL: url,
                        kind: .audio,
                        libraryItemID: Self.m2LongAudioLibraryID
                    ),
                    autoplay: !arguments.contains("--m2-no-autoplay")
                )
                if let seek = doubleValue(after: "--m2-seek-to", in: arguments) {
                    playback.seek(to: seek)
                }
            }
        }

        if arguments.contains("--m4-auto-open-in") {
            selectedTab = 3
            // Exercise the real open-in path with an external (non-inbox) copy.
            if let sourceURL = M4DebugSupport.makeOpenInSourceURL() {
                importCoordinator.handleOpenURL(sourceURL, modelContext: modelContext)
                M4DebugSupport.removeOpenInSource(sourceURL)
            }
        }

        if arguments.contains("--m4-foreground-write-inbox") {
            selectedTab = 3
            // Simulates a Finder copy that finishes after launch. The inbox
            // watcher must keep it pending until its size is stable.
            M4DebugSupport.startSlowInboxWriter()
        }

        if arguments.contains("--m4-seed-unsupported-inbox") {
            selectedTab = 3
        }
        #endif
    }

    private func doubleValue(after flag: String, in arguments: [String]) -> Double? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return Double(arguments[index + 1])
    }

    private func seedM3FixturesIfNeeded() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--m3-seed-playable-library") {
            M3DebugSeed.seedPlayableLibrary(in: modelContext)
        }
        if arguments.contains("--m3-seed-queue") {
            M3DebugSeed.seedQueue(in: session)
        }
        if arguments.contains("--m3-seed-single-queue") {
            M3DebugSeed.seedSingleQueue(in: modelContext, session: session)
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
