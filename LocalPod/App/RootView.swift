import SwiftUI
import SwiftData
import LocalPodKit

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ImportCoordinator.self) private var importCoordinator
    @Environment(PlaybackController.self) private var playback
    @Environment(PlaybackSession.self) private var session
    @Environment(AppIntentRouter.self) private var intentRouter

    @AppStorage(OnboardingStorage.completedKey) private var onboardingCompleted = false

    @State private var selectedTab = 0
    @State private var showSettings = false
    @State private var settingsDestination: SettingsDestination?
    @State private var showOnboarding = false
    @State private var didResolveOnboarding = false
    @State private var didRunLaunchAutomation = false
    @State private var didBootstrapPlayback = false

    var body: some View {
        // The custom bar is a layout sibling, not a floating inset: content
        // must not extend under it. A floating bar stays inside the window,
        // so XCUITest still reports covered controls as hittable and taps
        // land on the bar (see P2Chapter/M2 regressions). A sibling bar ends
        // the scroll viewport exactly where the bar begins, like the system
        // tab bar did.
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                LibraryView()
                    .tint(TapeTheme.ink)
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem { Label("资料库", systemImage: "books.vertical") }
                    .tag(0)

                PlaybackView(onGoToLibrary: { selectedTab = 0 })
                    .tint(TapeTheme.ink)
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem { Label(L10n.string("tab.playback"), systemImage: "play.circle") }
                    .tag(1)
            }
            .tint(Color.accentColor)

            TapeTabBar(selection: $selectedTab)
        }
        .sheet(isPresented: $showSettings) {
            // SwiftUI may build a sheet's content before it is presented and
            // keep that instance for later presentations. Without an identity
            // tie to the requested destination, a launch-argument deep link
            // (--m0-auto-benchmark / --m0-auto-inbox / --m1-auto-acceptance-
            // import / --m4-auto-open-in) would open Settings at its root:
            // the view was first created with a nil destination and its
            // NavigationPath state never picks the later value up.
            SettingsView(initialDestination: settingsDestination)
                .id(settingsDestination)
                .onDisappear { settingsDestination = nil }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(
                onContinue: { finishOnboarding() },
                onGoToImport: {
                    finishOnboarding()
                    openSettings(.importCenter)
                },
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
            didBootstrapPlayback = true
            // P2 debug seeds must exist BEFORE bootstrap so the launch
            // maintenance (reconcile → purgeExpired) sees them — the expired
            // trash fixture specifically exercises purge-at-launch.
            applyP2NotificationSettingsIfNeeded()
            seedP2FixturesIfNeeded()
            importCoordinator.bootstrap(modelContext: modelContext)
            seedDebugLibraryIfNeeded()
            seedM3FixturesIfNeeded()
            seedP1FixturesIfNeeded()
            seedP2BackupRoundTripIfNeeded()
            runLaunchAutomationIfNeeded()
            resolveOnboardingIfNeeded()
            // Local-only expiry reminder. This never prompts at launch: it
            // skips silently until the user enables notifications in Settings.
            await SigningReminder.refresh(
                expirationDate: SigningInfo.current()?.expirationDate,
                isEnabled: session.settings.signingReminderEnabled
            )
            // Intent requests are consumed only after the seeds above exist, so
            // a cold Siri launch can resolve seeded/debug collections.
            consumePendingAppIntentRequestIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                importCoordinator.runMaintenance(modelContext: modelContext)
                importCoordinator.importInboxIfNeeded(modelContext: modelContext)
                // Warm launch (Siri/Shortcuts while the app is alive): the
                // `.task` already ran, so consume any request staged by the
                // intent or an incoming URL.
                consumePendingAppIntentRequestIfNeeded()
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
            if url.scheme == "localpod" {
                if let request = AppIntentLaunchRequest(url: url) {
                    AppIntentLaunchRequestStore.save(request)
                }
                consumePendingAppIntentRequestIfNeeded()
            } else {
                importCoordinator.handleOpenURL(url, modelContext: modelContext)
            }
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

    /// Handles a pending Shortcuts/Siri or `localpod://` request exactly once.
    /// Cold launches call this at the end of `.task` (after debug/library
    /// seeds); warm launches call it on `.active` and from `onOpenURL`.
    private func consumePendingAppIntentRequestIfNeeded() {
        guard didBootstrapPlayback else { return }
        guard let request = AppIntentLaunchRequestStore.consume() else { return }
        switch request {
        case .continuePlayback:
            selectedTab = 1
            _ = session.resumeForShortcut()
        case .openCollection(let name):
            selectedTab = 0
            intentRouter.requestCollection(named: name)
        }
    }

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

    private func openSettings(_ destination: SettingsDestination? = nil) {
        settingsDestination = destination
        showSettings = true
    }

    /// Debug-only launch switches used by UI tests and manual simulator
    /// validation. They have no effect in Release builds.
    private func runLaunchAutomationIfNeeded() {
        #if DEBUG
        guard !didRunLaunchAutomation else { return }
        didRunLaunchAutomation = true
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("--m1-auto-acceptance-import") {
            openSettings(.diagnostics)
            importCoordinator.importAcceptanceFolder(modelContext: modelContext)
        } else if arguments.contains("--m0-auto-demo-import") {
            openSettings(.diagnostics)
            importCoordinator.importDemoFolder(modelContext: modelContext)
        }

        if arguments.contains("--m0-auto-benchmark") {
            openSettings(.diagnostics)
        }

        if arguments.contains("--m0-auto-inbox") {
            openSettings(.inbox)
        } else if arguments.contains("--m1-auto-maintenance") {
            openSettings(.diagnostics)
        }

        if arguments.contains("--m1-seed-library-5000") {
            selectedTab = 0
        }

        if arguments.contains("--m0-auto-play-audio") {
            selectedTab = 1
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

        if arguments.contains("--p2-chapter-playback") {
            selectedTab = 1
            if let url = Bundle.main.url(
                forResource: "demo-chaptered-audio",
                withExtension: "m4a"
            ) {
                playback.load(
                    PlaybackItem(
                        title: L10n.string("playback.demo.chapterTitle"),
                        subtitle: L10n.string("playback.demo.launchArgumentSubtitle"),
                        fileURL: url,
                        kind: .audio
                    ),
                    autoplay: true
                )
            }
        }

        if arguments.contains("--m3-open-settings") {
            openSettings()
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
            selectedTab = 1
            session.playQueueItem(
                itemID: session.queue.currentItemID ?? M3DebugSeed.itemA
            )
        }

        if arguments.contains("--m2-auto-play-long-audio") {
            selectedTab = 1
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
            openSettings(.inbox)
            // Exercise the real open-in path with an external (non-inbox) copy.
            if let sourceURL = M4DebugSupport.makeOpenInSourceURL() {
                importCoordinator.handleOpenURL(sourceURL, modelContext: modelContext)
                M4DebugSupport.removeOpenInSource(sourceURL)
            }
        }

        if arguments.contains("--m4-foreground-write-inbox") {
            openSettings(.inbox)
            // Simulates a Finder copy that finishes after launch. The inbox
            // watcher must keep it pending until its size is stable.
            M4DebugSupport.startSlowInboxWriter()
        }

        if arguments.contains("--m4-seed-unsupported-inbox") {
            openSettings(.inbox)
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

    private func seedP1FixturesIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--p1-seed-smart-playlists") {
            P1DebugSeed.seedSmartPlaylists(in: modelContext)
        }
        #endif
    }

    private func seedP2FixturesIfNeeded() {
        #if DEBUG
        P2DebugSeed.seedLinkedFolderIfRequested(in: modelContext)
        P2DebugSeed.addFileToLinkedFolderIfRequested(in: modelContext)
        P2DebugSeed.seedTrashIfRequested(in: modelContext)
        P2DebugSeed.seedExpiredTrashIfRequested(in: modelContext)
        #endif
    }

    /// UI-test seam: turn the import notification setting on without going
    /// through the Settings toggle, which would request system authorization
    /// and show a springboard alert. Delivery still checks the real
    /// authorization status, so no notification is posted in the simulator.
    /// Must run before bootstrap so an inbox import cannot finish first.
    private func applyP2NotificationSettingsIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--p2-enable-import-notifications") {
            session.settings.importNotificationsEnabled = true
        }
        #endif
    }

    /// Backup/restore round-trip seam (--p2-export-backup / --p2-import-backup).
    /// Export runs after the seeds so it snapshots the seeded library; import
    /// runs at the same point on the second launch, where bootstrap
    /// maintenance has already re-marked restored rows missing when the media
    /// files are gone.
    private func seedP2BackupRoundTripIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--p2-import-backup") {
            P2DebugSeed.importBackupIfRequested(in: modelContext)
        }
        P2DebugSeed.exportBackupIfRequested(in: modelContext)
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
