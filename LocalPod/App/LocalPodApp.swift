import SwiftUI
import SwiftData
import LocalPodKit

@main
struct LocalPodApp: App {
    @State private var importCoordinator = ImportCoordinator()
    @State private var session = PlaybackSession()
    private let container: ModelContainer

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--m0-reset-data") {
            Self.resetDebugData()
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
        for directory in ["Media", "DemoInput", "AcceptanceInput", "ImportStaging", "ImportReports"] {
            try? FileManager.default.removeItem(
                at: supportRoot.appendingPathComponent(directory, isDirectory: true)
            )
        }
        try? FileManager.default.removeItem(
            at: MediaStorage.live.cachesRoot.appendingPathComponent("Artwork", isDirectory: true)
        )
        AppSettingsStore.clearStoredValues()
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
                .environment(session.playback)
                .environment(session.queue)
                .environment(session.settings)
                .environment(session.sleepTimer)
        }
        .modelContainer(container)
    }
}
