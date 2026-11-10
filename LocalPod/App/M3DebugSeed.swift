#if DEBUG
import Foundation
import SwiftData
import LocalPodKit

/// Deterministic library/queue fixtures for M3 UI tests. Only compiled in
/// Debug builds and only invoked by explicit launch arguments.
@MainActor
enum M3DebugSeed {
    static let itemA = UUID(uuidString: "33333333-3333-4333-8333-333333333301")!
    static let itemB = UUID(uuidString: "33333333-3333-4333-8333-333333333302")!
    static let itemC = UUID(uuidString: "33333333-3333-4333-8333-333333333303")!
    static let itemLong = UUID(uuidString: "33333333-3333-4333-8333-333333333304")!
    static let itemIDs = [itemA, itemB, itemC]

    static func seedPlayableLibrary(in context: ModelContext) {
        guard let source = Bundle.main.url(forResource: "demo-audio", withExtension: "m4a"),
              let mediaRoot = try? MediaStorage.live.mediaRootURL() else {
            return
        }

        let titles = ["队列测试 A", "队列测试 B", "队列测试 C"]
        for (index, itemID) in itemIDs.enumerated() {
            let fileName = "\(itemID.uuidString).m4a"
            let destination = mediaRoot.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.copyItem(at: source, to: destination)
            }

            var descriptor = FetchDescriptor<MediaItem>(
                predicate: #Predicate { $0.id == itemID }
            )
            descriptor.fetchLimit = 1
            if (try? context.fetch(descriptor).first) != nil {
                continue
            }
            context.insert(MediaItem(
                id: itemID,
                title: titles[index],
                sortTitle: titles[index],
                originalFileName: fileName,
                relativePath: "Media/\(fileName)",
                relativeFolderPath: "",
                kind: .audio,
                fileExtension: "m4a",
                byteSize: 220_000,
                durationSeconds: 20,
                folderName: "M3 测试",
                source: .imported,
                sourceName: "M3 测试"
            ))
        }

        // Continue-listening fixture: B is finished and must be hidden; C is
        // in progress and must appear.
        let states = (try? context.fetch(FetchDescriptor<PlaybackState>())) ?? []
        if !states.contains(where: { $0.itemID == itemB }) {
            context.insert(PlaybackState(
                itemID: itemB,
                position: 20,
                duration: 20,
                isFinished: true,
                playCount: 1,
                lastPlayedAt: Date()
            ))
        }
        if !states.contains(where: { $0.itemID == itemC }) {
            context.insert(PlaybackState(
                itemID: itemC,
                position: 6,
                duration: 20,
                isFinished: false,
                playCount: 1,
                lastPlayedAt: Date().addingTimeInterval(-60)
            ))
        }
        try? context.save()
    }

    static func seedQueue(in session: PlaybackSession) {
        session.queue.setQueue(itemIDs: itemIDs, current: itemA)
    }

    /// Single-item queue backed by the 298s fixture so a real one-minute
    /// sleep timer can fire while audio is still playing.
    static func seedSingleQueue(in context: ModelContext, session: PlaybackSession) {
        guard let source = Bundle.main.url(
            forResource: "demo-long-audio",
            withExtension: "m4a"
        ), let mediaRoot = try? MediaStorage.live.mediaRootURL() else {
            // Fall back to the short fixture so the test still exercises the
            // queue rather than silently doing nothing.
            session.queue.setQueue(itemIDs: [itemA], current: itemA)
            return
        }

        let fileName = "\(itemLong.uuidString).m4a"
        let destination = mediaRoot.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.copyItem(at: source, to: destination)
        }

        var descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.id == itemLong }
        )
        descriptor.fetchLimit = 1
        if (try? context.fetch(descriptor).first) == nil {
            context.insert(MediaItem(
                id: itemLong,
                title: "睡眠测试长音频",
                sortTitle: "睡眠测试长音频",
                originalFileName: fileName,
                relativePath: "Media/\(fileName)",
                relativeFolderPath: "",
                kind: .audio,
                fileExtension: "m4a",
                byteSize: 1_500_000,
                durationSeconds: 298,
                folderName: "M3 测试",
                source: .imported,
                sourceName: "M3 测试"
            ))
            try? context.save()
        }

        session.queue.setQueue(itemIDs: [itemLong], current: itemLong)
    }
}
#endif
