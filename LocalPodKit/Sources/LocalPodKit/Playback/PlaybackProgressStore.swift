import Foundation
import SwiftData

/// Small persistence façade for per-item playback progress. It is deliberately
/// separate from `LibraryService`: progress writes happen every second during
/// playback and must not invalidate `MediaItem` rows/observed library lists.
@MainActor
public final class PlaybackProgressStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func state(for itemID: UUID) throws -> PlaybackState? {
        var descriptor = FetchDescriptor<PlaybackState>(
            predicate: #Predicate { $0.itemID == itemID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Position at which playback should resume, or 0 when the item is new,
    /// finished, or too close to the end.
    public func resumePosition(
        for itemID: UUID,
        fallbackDuration: Double? = nil
    ) throws -> Double {
        guard let state = try state(for: itemID) else { return 0 }
        let duration = state.duration > 0
            ? state.duration
            : max(fallbackDuration ?? 0, 0)
        return PlaybackPolicy.resumePosition(
            position: state.position,
            duration: duration,
            isFinished: state.isFinished
        )
    }

    /// Called once per loaded item when playback actually starts. Counts a
    /// play and clears a previous "finished" flag so a replayed episode starts
    /// fresh.
    @discardableResult
    public func recordPlayStart(
        itemID: UUID,
        duration: Double
    ) throws -> PlaybackState {
        let state = try findOrCreate(itemID: itemID)
        if state.isFinished {
            state.isFinished = false
            state.position = 0
        }
        state.playCount += 1
        state.lastPlayedAt = Date()
        state.updatedAt = Date()
        if duration.isFinite, duration > 0 {
            state.duration = duration
        }
        try context.save()
        return state
    }

    @discardableResult
    public func save(
        itemID: UUID,
        position: Double,
        duration: Double,
        isFinished: Bool
    ) throws -> PlaybackState {
        let state = try findOrCreate(itemID: itemID)
        let safeDuration: Double
        if duration.isFinite, duration > 0 {
            safeDuration = duration
        } else {
            safeDuration = state.duration
        }
        let upperBound = safeDuration > 0 ? safeDuration : max(position, 0)
        let safePosition = position.isFinite
            ? min(max(position, 0), upperBound)
            : 0
        state.position = safePosition
        if safeDuration > 0 {
            state.duration = safeDuration
        }
        state.isFinished = isFinished
        state.updatedAt = Date()
        try context.save()
        return state
    }

    public func markFinished(itemID: UUID, duration: Double) throws {
        let state = try findOrCreate(itemID: itemID)
        if duration.isFinite, duration > 0 {
            state.duration = duration
        }
        state.position = state.duration
        state.isFinished = true
        state.updatedAt = Date()
        try context.save()
    }

    public func deleteState(for itemID: UUID) throws {
        guard let state = try state(for: itemID) else { return }
        context.delete(state)
        try context.save()
    }

    private func findOrCreate(itemID: UUID) throws -> PlaybackState {
        if let existing = try state(for: itemID) {
            return existing
        }
        let state = PlaybackState(itemID: itemID)
        context.insert(state)
        return state
    }
}
