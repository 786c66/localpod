#if DEBUG
import Foundation
import SwiftData
import LocalPodKit

/// Deterministic fixtures for the P1 smart-playlist UI tests. Only compiled in
/// Debug builds and only applied when the launch argument asks for it.
@MainActor
enum P1DebugSeed {
    static let collectionA = "智能合集 A"
    static let collectionB = "智能合集 B"

    /// Stages a completed browser batch before RootView bootstraps, exercising
    /// launch recovery and the shared WiFi -> ImportCoordinator path without a
    /// real network connection.
    static func stageWiFiUploadIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--p1-wifi-staged-upload") else {
            return
        }
        guard let source = Bundle.main.url(
            forResource: "demo-audio",
            withExtension: "m4a"
        ), let data = try? Data(contentsOf: source) else {
            return
        }
        do {
            let store = WiFiUploadStorage.store
            let session = try store.createSession()
            let sink = try store.beginFile(
                sessionID: session.id,
                relativePath: "Wi-Fi 测试/Wi-Fi 示例.m4a",
                expectedBytes: Int64(data.count)
            )
            try sink.append(data)
            _ = try sink.finish()
            _ = try store.completeSession(session.id)
        } catch {
            // Debug-only fixture; a failed setup simply leaves the UI test
            // without seeded content (which it will report).
        }
    }

    static func seedSmartPlaylists(in context: ModelContext) {
        let itemIDs = Set(M3DebugSeed.itemIDs)
        let items = (try? context.fetch(FetchDescriptor<MediaItem>()))?
            .filter { itemIDs.contains($0.id) } ?? []
        guard !items.isEmpty else { return }

        let collectionA = ensureCollection(named: collectionA, in: context)
        let collectionB = ensureCollection(named: collectionB, in: context)
        for item in items {
            if item.id == M3DebugSeed.itemB {
                item.collectionID = collectionB.id
            } else {
                item.collectionID = collectionA.id
            }
        }
        try? context.save()
    }

    private static func ensureCollection(
        named name: String,
        in context: ModelContext
    ) -> MediaCollection {
        let key = MediaCollection.normalizedKey(for: name)
        let collections = (try? context.fetch(FetchDescriptor<MediaCollection>())) ?? []
        if let existing = collections.first(where: { $0.nameKey == key }) {
            return existing
        }
        let collection = MediaCollection(name: name, nameKey: key)
        context.insert(collection)
        return collection
    }
}
#endif
