import SwiftUI
import SwiftData
import LocalPodKit

@main
struct LocalPodApp: App {
    @State private var importCoordinator = ImportCoordinator()
    @State private var session = PlaybackSession()
    @State private var intentRouter = AppIntentRouter()
    private let container: ModelContainer

    init() {
        #if DEBUG
        let launchArguments = ProcessInfo.processInfo.arguments
        if launchArguments.contains("--m0-reset-data") {
            Self.resetDebugData()
        }
        // First-run onboarding must not block the M0-M4 UI suites, which all
        // reset app data. --m0-reset-data therefore marks onboarding done;
        // only the dedicated M5 argument clears it again for the show-once
        // test.
        if launchArguments.contains("--m5-reset-onboarding") {
            UserDefaults.standard.removeObject(forKey: OnboardingStorage.completedKey)
        }
        // UI-test seam for Shortcuts/Siri: stage the same request the App
        // Intent would persist, then let RootView consume it through the
        // normal path once the library fixtures exist.
        let appIntentPrefix = "--p2-app-intent="
        if let argument = launchArguments.first(where: { $0.hasPrefix(appIntentPrefix) }),
           let request = AppIntentLaunchRequest(
               rawValue: String(argument.dropFirst(appIntentPrefix.count))
           ) {
            AppIntentLaunchRequestStore.save(request)
        }
        #endif
        do {
            container = try LocalPodStore.makeContainer()
        } catch {
            fatalError("无法创建 SwiftData 容器：\(error)")
        }
        _ = try? ImportInbox.live.ensureExists()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--m0-seed-inbox") {
            Self.seedDebugInbox()
        }
        if ProcessInfo.processInfo.arguments.contains("--m4-seed-unsupported-inbox") {
            M4DebugSupport.seedUnsupportedInbox()
        }
        P1DebugSeed.stageWiFiUploadIfRequested()
        #endif
    }

    #if DEBUG
    private static func seedDebugInbox() {
        guard let source = Bundle.main.url(forResource: "demo-audio", withExtension: "m4a"),
              let inbox = try? ImportInbox.live.ensureExists() else {
            return
        }
        let destination = inbox.appendingPathComponent("FromFinder.m4a")
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: source, to: destination)
    }

    private static func resetDebugData() {
        LocalPodStore.deleteDefaultStoreFiles()
        let supportRoot = MediaStorage.live.applicationSupportRoot
        for directory in [
            "Media",
            "DemoInput",
            "AcceptanceInput",
            "ImportStaging",
            "ImportReports",
            "WiFiUploads",
            "Trash"
        ] {
            try? FileManager.default.removeItem(
                at: supportRoot.appendingPathComponent(directory, isDirectory: true)
            )
        }
        try? FileManager.default.removeItem(
            at: MediaStorage.live.cachesRoot.appendingPathComponent("Artwork", isDirectory: true)
        )
        AppSettingsStore.clearStoredValues()
        // A pending Shortcuts/Siri request is per-launch state; never let a
        // failed/terminated test leak it into the next one.
        AppIntentLaunchRequestStore.clear()
        // Keep UI-test resets onboarding-free: resetting media data is not a
        // first install. `--m5-reset-onboarding` opts into first-run instead.
        UserDefaults.standard.set(true, forKey: OnboardingStorage.completedKey)
        // Removing the whole inbox also clears `.Skipped` quarantine items and
        // any hidden `.localpod-stage-*` leftovers from an interrupted run.
        try? FileManager.default.removeItem(at: ImportInbox.live.directoryURL)
        _ = try? ImportInbox.live.ensureExists()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(importCoordinator)
                .environment(session)
                .environment(intentRouter)
                .environment(session.playback)
                .environment(session.queue)
                .environment(session.settings)
                .environment(session.sleepTimer)
        }
        .modelContainer(container)
    }
}
