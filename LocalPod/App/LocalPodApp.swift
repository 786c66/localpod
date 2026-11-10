import SwiftUI
import SwiftData
import LocalPodKit

@main
struct LocalPodApp: App {
    @State private var importCoordinator = ImportCoordinator()
    @State private var playback = PlaybackController()
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
        try? FileManager.default.removeItem(
            at: supportRoot.appendingPathComponent("Media", isDirectory: true)
        )
        try? FileManager.default.removeItem(
            at: supportRoot.appendingPathComponent("DemoInput", isDirectory: true)
        )
        _ = try? ImportInbox.live.ensureExists()
        if let pending = try? ImportInbox.live.pendingURLs() {
            for url in pending {
                try? ImportInbox.live.remove(url)
            }
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(importCoordinator)
                .environment(playback)
        }
        .modelContainer(container)
    }
}
