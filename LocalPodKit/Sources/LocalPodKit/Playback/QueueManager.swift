import Foundation
import SwiftData

/// Ordered play queue with SwiftData persistence.
///
/// Semantics (M3):
/// - `setQueue` replaces the queue (used by "play all" and by playing an item
///   directly from the library);
/// - `insertNext` puts an item immediately after the current item;
/// - `append` puts an item at the tail;
/// - auto-advance follows `repeatMode` and, when enabled, the persisted
///   shuffle order.
///
/// Item IDs in a queue are unique. Adding an item that is already queued moves
/// the existing entry instead of creating a duplicate, which keeps "current
/// item" unambiguous after a restart.
@MainActor
@Observable
public final class QueueManager {
    public struct Entry: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let itemID: UUID

        public init(id: UUID = UUID(), itemID: UUID) {
            self.id = id
            self.itemID = itemID
        }
    }

    public private(set) var entries: [Entry] = []
    public private(set) var currentItemID: UUID?
    public private(set) var shuffleEnabled = false
    public private(set) var repeatMode: QueueRepeatMode = .off

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var shuffleOrder: [UUID] = []

    public static let stateKey = "main"

    public init() {}

    public var count: Int { entries.count }

    public var isEmpty: Bool { entries.isEmpty }

    public var currentEntry: Entry? {
        guard let currentItemID else { return nil }
        return entries.first { $0.itemID == currentItemID }
    }

    public var currentIndex: Int? {
        guard let currentItemID else { return nil }
        return entries.firstIndex { $0.itemID == currentItemID }
    }

    public var itemIDs: [UUID] {
        entries.map(\.itemID)
    }

    /// The order the user is currently hearing. Shuffle order when enabled,
    /// natural queue order otherwise.
    public var playOrder: [UUID] {
        if shuffleEnabled {
            let live = Set(itemIDs)
            return shuffleOrder.filter { live.contains($0) }
        }
        return itemIDs
    }

    // MARK: - Attachment and persistence

    public func attach(context: ModelContext) {
        self.context = context
        reload()
    }

    public func detach() {
        context = nil
        entries = []
        currentItemID = nil
        shuffleEnabled = false
        repeatMode = .off
        shuffleOrder = []
    }

    private func reload() {
        guard let context else { return }
        let rows = (try? context.fetch(FetchDescriptor<QueueEntry>(
            sortBy: [SortDescriptor(\.position)]
        ))) ?? []
        entries = rows.map { Entry(id: $0.id, itemID: $0.itemID) }

        var descriptor = FetchDescriptor<QueueState>(
            predicate: #Predicate { $0.key == "main" }
        )
        descriptor.fetchLimit = 1
        let state = (try? context.fetch(descriptor))?.first

        shuffleEnabled = state?.shuffleEnabled ?? false
        repeatMode = QueueRepeatMode(
            rawValue: state?.repeatModeRaw ?? QueueRepeatMode.off.rawValue
        ) ?? .off
        shuffleOrder = (state?.shuffleOrderRaw ?? "")
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }

        let live = Set(itemIDs)
        shuffleOrder = shuffleOrder.filter { live.contains($0) }
        if let stored = state?.currentItemID, live.contains(stored) {
            currentItemID = stored
        } else {
            currentItemID = entries.first?.itemID
        }

        if shuffleEnabled {
            let known = Set(shuffleOrder)
            if shuffleOrder.isEmpty || known != live {
                rebuildShuffleOrder(startingWith: currentItemID)
            }
        } else {
            shuffleOrder = []
        }
    }

    private func persist() {
        guard let context else { return }

        let rows = (try? context.fetch(FetchDescriptor<QueueEntry>())) ?? []
        var byID: [UUID: QueueEntry] = [:]
        for row in rows {
            byID[row.id] = row
        }

        var kept = Set<UUID>()
        for (index, entry) in entries.enumerated() {
            kept.insert(entry.id)
            if let row = byID[entry.id] {
                row.itemID = entry.itemID
                row.position = index
            } else {
                context.insert(QueueEntry(id: entry.id, itemID: entry.itemID, position: index))
            }
        }
        for row in rows where !kept.contains(row.id) {
            context.delete(row)
        }

        var descriptor = FetchDescriptor<QueueState>(
            predicate: #Predicate { $0.key == "main" }
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
        state.currentItemID = currentItemID
        state.shuffleEnabled = shuffleEnabled
        state.repeatModeRaw = repeatMode.rawValue
        state.shuffleOrderRaw = shuffleOrder.map(\.uuidString).joined(separator: ",")
        state.updatedAt = Date()

        try? context.save()
    }

    // MARK: - Queue mutations

    public func setQueue(
        itemIDs: [UUID],
        current: UUID? = nil,
        shuffle: Bool? = nil,
        repeatMode: QueueRepeatMode? = nil
    ) {
        var seen = Set<UUID>()
        let uniqueIDs = itemIDs.filter { seen.insert($0).inserted }
        entries = uniqueIDs.map { Entry(itemID: $0) }
        if let repeatMode {
            self.repeatMode = repeatMode
        }
        if let shuffle {
            shuffleEnabled = shuffle
        }
        let requested = current ?? uniqueIDs.first
        currentItemID = requested.flatMap { uniqueIDs.contains($0) ? $0 : nil }
        if shuffleEnabled {
            rebuildShuffleOrder(startingWith: currentItemID)
        } else {
            shuffleOrder = []
        }
        persist()
    }

    /// "Play next": move or insert the item immediately after the current one.
    public func insertNext(_ itemID: UUID) {
        removeExisting(itemID)
        guard let current = currentItemID,
              let index = entries.firstIndex(where: { $0.itemID == current }) else {
            append(itemID)
            return
        }
        entries.insert(Entry(itemID: itemID), at: index + 1)
        if shuffleEnabled {
            let orderIndex = shuffleOrder.firstIndex(of: current) ?? -1
            shuffleOrder.insert(itemID, at: min(orderIndex + 1, shuffleOrder.count))
        }
        persist()
    }

    /// "Add to queue": append at the tail (or start a queue when empty).
    public func append(_ itemID: UUID) {
        removeExisting(itemID)
        entries.append(Entry(itemID: itemID))
        if currentItemID == nil {
            currentItemID = itemID
        }
        if shuffleEnabled {
            shuffleOrder.append(itemID)
        }
        persist()
    }

    /// Removes an item without selecting a replacement. Used for non-current
    /// item deletion; callers that delete the current item use
    /// `removeCurrentAndAdvance()`.
    public func remove(itemID: UUID) {
        let wasCurrent = currentItemID == itemID
        entries.removeAll { $0.itemID == itemID }
        shuffleOrder.removeAll { $0 == itemID }
        if wasCurrent {
            currentItemID = entries.first?.itemID
        }
        persist()
    }

    public func setCurrent(_ itemID: UUID) {
        guard entries.contains(where: { $0.itemID == itemID }) else { return }
        currentItemID = itemID
        persist()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        entries.moveElements(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Removes one queue entry. Returns `true` when the removed entry was the
    /// current item, in which case a replacement (if any) is already current.
    @discardableResult
    public func removeEntry(id entryID: UUID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            return false
        }
        let removed = entries[index]
        let wasCurrent = removed.itemID == currentItemID
        let nextInOrder = shuffleEnabled
            ? playOrderCandidate(after: removed.itemID)
            : nil
        entries.remove(at: index)
        shuffleOrder.removeAll { $0 == removed.itemID }
        if wasCurrent {
            let replacement: UUID?
            if let nextInOrder,
               entries.contains(where: { $0.itemID == nextInOrder }) {
                replacement = nextInOrder
            } else if entries.indices.contains(index) {
                replacement = entries[index].itemID
            } else {
                replacement = entries.last?.itemID
            }
            currentItemID = replacement
        }
        persist()
        return wasCurrent
    }

    /// Current item deletion: remove it and select the next item. Returns the
    /// replacement item ID, or nil when the queue becomes empty.
    public func removeCurrentAndAdvance() -> UUID? {
        guard let currentItemID,
              let index = entries.firstIndex(where: { $0.itemID == currentItemID }) else {
            return currentItemID
        }
        let next = shuffleEnabled ? playOrderCandidate(after: currentItemID) : nil
        entries.remove(at: index)
        shuffleOrder.removeAll { $0 == currentItemID }
        if let next, entries.contains(where: { $0.itemID == next }) {
            self.currentItemID = next
        } else if entries.indices.contains(index) {
            self.currentItemID = entries[index].itemID
        } else {
            self.currentItemID = entries.last?.itemID
        }
        persist()
        return self.currentItemID
    }

    public func clear() {
        entries = []
        currentItemID = nil
        shuffleOrder = []
        persist()
    }

    // MARK: - Advance / repeat / shuffle

    public func advance() -> UUID? {
        guard !entries.isEmpty else {
            currentItemID = nil
            persist()
            return nil
        }
        guard let current = currentItemID else {
            currentItemID = playOrder.first ?? entries.first?.itemID
            persist()
            return currentItemID
        }
        if repeatMode == .one {
            return current
        }
        if let next = playOrderCandidate(after: current) {
            currentItemID = next
            persist()
            return next
        }
        if repeatMode == .all, let first = playOrder.first {
            currentItemID = first
            persist()
            return first
        }
        return nil
    }

    public func previous() -> UUID? {
        guard !entries.isEmpty else { return nil }
        let order = playOrder
        guard let current = currentItemID,
              let index = order.firstIndex(of: current) else {
            if let first = order.first {
                currentItemID = first
                persist()
                return first
            }
            return nil
        }
        if index > 0 {
            let previous = order[index - 1]
            currentItemID = previous
            persist()
            return previous
        }
        if repeatMode == .all, let last = order.last {
            currentItemID = last
            persist()
            return last
        }
        return nil
    }

    public func setShuffle(_ enabled: Bool) {
        guard enabled != shuffleEnabled else { return }
        shuffleEnabled = enabled
        if enabled {
            rebuildShuffleOrder(startingWith: currentItemID)
        } else {
            shuffleOrder = []
        }
        persist()
    }

    public func setRepeatMode(_ mode: QueueRepeatMode) {
        repeatMode = mode
        persist()
    }

    public func cycleRepeatMode() {
        switch repeatMode {
        case .off: setRepeatMode(.all)
        case .all: setRepeatMode(.one)
        case .one: setRepeatMode(.off)
        }
    }

    // MARK: - Helpers

    private func playOrderCandidate(after itemID: UUID) -> UUID? {
        let order = playOrder
        guard let index = order.firstIndex(of: itemID),
              order.indices.contains(index + 1) else {
            return nil
        }
        return order[index + 1]
    }

    private func removeExisting(_ itemID: UUID) {
        entries.removeAll { $0.itemID == itemID }
        shuffleOrder.removeAll { $0 == itemID }
    }

    private func rebuildShuffleOrder(startingWith itemID: UUID?) {
        var rest = itemIDs
        if let itemID, let index = rest.firstIndex(of: itemID) {
            rest.remove(at: index)
            rest.shuffle()
            shuffleOrder = [itemID] + rest
        } else {
            rest.shuffle()
            shuffleOrder = rest
        }
    }
}
