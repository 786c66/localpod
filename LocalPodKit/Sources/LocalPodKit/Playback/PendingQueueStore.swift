import Foundation
import SwiftData

/// One entry of a queue restored from a backup whose media is not available
/// yet. `fingerprint` lets the entry reconnect even when the restored item row
/// was later replaced by a re-import of the same file.
public struct PendingQueueEntry: Codable, Sendable, Equatable {
    public var itemID: UUID
    public var fingerprint: String?

    public init(itemID: UUID, fingerprint: String? = nil) {
        self.itemID = itemID
        self.fingerprint = fingerprint
    }
}

/// Persists a restored queue while its media is missing and promotes it back
/// to the live queue once every entry resolves to a present library item.
///
/// A backup restored on a fresh install creates `MediaItem` rows with
/// `isMissing = true` because no media file exists yet. Writing that queue as
/// live state would let the destructive launch path drop every unplayable
/// entry, so the queue is parked here instead. `LibraryService` calls
/// `applyIfPossible` after import relinks and after maintenance relinks; the
/// first call where all media is present installs the queue and notifies
/// `PlaybackSession` so the UI updates without a relaunch.
@MainActor
public enum PendingQueueStore {
    public static let stateKey = "restore"
    public static let didApplyNotification = Notification.Name(
        "LocalPodKit.pendingQueueDidApply"
    )

    public struct Snapshot: Sendable, Equatable {
        public var entries: [PendingQueueEntry]
        public var currentItemID: UUID?
        public var shuffleEnabled: Bool
        public var repeatModeRaw: String
        public var shuffleOrder: [UUID]

        public init(
            entries: [PendingQueueEntry],
            currentItemID: UUID?,
            shuffleEnabled: Bool,
            repeatModeRaw: String,
            shuffleOrder: [UUID]
        ) {
            self.entries = entries
            self.currentItemID = currentItemID
            self.shuffleEnabled = shuffleEnabled
            self.repeatModeRaw = repeatModeRaw
            self.shuffleOrder = shuffleOrder
        }
    }

    /// Replaces any parked queue. An empty queue clears the snapshot.
    public static func save(_ snapshot: Snapshot, in context: ModelContext) {
        guard !snapshot.entries.isEmpty else {
            clear(in: context)
            return
        }
        let entriesData = (try? JSONEncoder().encode(snapshot.entries)) ?? Data()
        let row = fetchRow(in: context) ?? {
            let created = PendingQueueSnapshot()
            context.insert(created)
            return created
        }()
        row.entriesData = entriesData
        row.currentItemID = snapshot.currentItemID
        row.shuffleEnabled = snapshot.shuffleEnabled
        row.repeatModeRaw = snapshot.repeatModeRaw
        row.shuffleOrderRaw = snapshot.shuffleOrder
            .map(\.uuidString)
            .joined(separator: ",")
        row.updatedAt = Date()
        try? context.save()
    }

    public static func clear(in context: ModelContext) {
        guard let row = fetchRow(in: context) else { return }
        context.delete(row)
        try? context.save()
    }

    public static func hasPending(in context: ModelContext) -> Bool {
        fetchRow(in: context) != nil
    }

    /// Decoded parked queue, or nil when nothing is pending (or the payload
    /// cannot be read).
    public static func pending(in context: ModelContext) -> Snapshot? {
        guard let row = fetchRow(in: context),
              let entries = try? JSONDecoder().decode(
                  [PendingQueueEntry].self,
                  from: row.entriesData
              ),
              !entries.isEmpty else {
            return nil
        }
        return Snapshot(
            entries: entries,
            currentItemID: row.currentItemID,
            shuffleEnabled: row.shuffleEnabled,
            repeatModeRaw: row.repeatModeRaw,
            shuffleOrder: row.shuffleOrderRaw
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
        )
    }

    /// Installs the parked queue when every entry resolves to a library item
    /// whose media is present. Returns false while anything is still missing;
    /// the next relink attempt tries again.
    @discardableResult
    public static func applyIfPossible(in context: ModelContext) -> Bool {
        guard let snapshot = pending(in: context) else { return false }
        // Never overwrite a queue the user built after the restore.
        let liveQueueCount = (try? context.fetchCount(FetchDescriptor<QueueEntry>())) ?? 0
        guard liveQueueCount == 0 else { return false }

        var remap: [UUID: UUID] = [:]
        var orderedIDs: [UUID] = []
        var seen = Set<UUID>()
        for entry in snapshot.entries {
            guard let item = resolve(entry, in: context), !item.isMissing else {
                return false
            }
            remap[entry.itemID] = item.id
            if seen.insert(item.id).inserted {
                orderedIDs.append(item.id)
            }
        }
        guard let firstID = orderedIDs.first else { return false }

        for row in (try? context.fetch(FetchDescriptor<QueueEntry>())) ?? [] {
            context.delete(row)
        }
        for (index, itemID) in orderedIDs.enumerated() {
            context.insert(QueueEntry(itemID: itemID, position: index))
        }

        let queueStateKey = QueueManager.stateKey
        var descriptor = FetchDescriptor<QueueState>(
            predicate: #Predicate { $0.key == queueStateKey }
        )
        descriptor.fetchLimit = 1
        let state: QueueState
        if let existing = try? context.fetch(descriptor).first {
            state = existing
        } else {
            let created = QueueState()
            context.insert(created)
            state = created
        }
        state.currentItemID = snapshot.currentItemID
            .flatMap { remap[$0] }
            .flatMap { orderedIDs.contains($0) ? $0 : nil } ?? firstID
        state.shuffleEnabled = snapshot.shuffleEnabled
        state.repeatModeRaw = QueueRepeatMode(rawValue: snapshot.repeatModeRaw)?
            .rawValue ?? QueueRepeatMode.off.rawValue
        let live = Set(orderedIDs)
        state.shuffleOrderRaw = snapshot.shuffleOrder
            .compactMap { remap[$0] ?? $0 }
            .filter { live.contains($0) }
            .map(\.uuidString)
            .joined(separator: ",")
        state.updatedAt = Date()

        if let row = fetchRow(in: context) {
            context.delete(row)
        }
        try? context.save()
        NotificationCenter.default.post(name: didApplyNotification, object: nil)
        return true
    }

    private static func fetchRow(in context: ModelContext) -> PendingQueueSnapshot? {
        var descriptor = FetchDescriptor<PendingQueueSnapshot>(
            predicate: #Predicate { $0.key == "restore" }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func resolve(
        _ entry: PendingQueueEntry,
        in context: ModelContext
    ) -> MediaItem? {
        var descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.id == entry.itemID }
        )
        descriptor.fetchLimit = 1
        if let item = try? context.fetch(descriptor).first {
            return item
        }
        guard let fingerprint = entry.fingerprint else { return nil }
        var fingerprintDescriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.fingerprint == fingerprint }
        )
        fingerprintDescriptor.fetchLimit = 1
        return try? context.fetch(fingerprintDescriptor).first
    }
}
