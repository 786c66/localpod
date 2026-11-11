import Foundation

/// A built-in smart playlist: a dynamic library view rather than a persisted
/// entity.
///
/// Smart playlists are computed from ``SmartPlaylistEntry`` snapshots whenever
/// the library or playback state changes, so they need no SwiftData schema
/// version and never go stale. Display names are owned by the app; this file
/// contains no user-facing strings.
public enum SmartPlaylistKind: String, CaseIterable, Identifiable, Sendable {
    /// In-progress items with at least one play, most recently played first.
    /// The app normally shows a short prefix of this list (for example five
    /// rows) via `limit`; the engine itself has no default UI limit.
    case continueListening
    /// Every in-progress item with at least one play, in the same order as
    /// ``continueListening``. The two kinds intentionally share one predicate:
    /// "continue listening" is the short recent view, "unfinished" is the full
    /// list.
    case unfinished
    /// Items added inside the recent window, newest first.
    case recentlyAdded
    /// Items whose playback state is marked finished, most recently played
    /// first.
    case finished

    public var id: String { rawValue }

    /// SF Symbol the app uses for this smart playlist.
    public var symbolName: String {
        switch self {
        case .continueListening: "play.circle"
        case .unfinished: "clock"
        case .recentlyAdded: "sparkles"
        case .finished: "checkmark.circle"
        }
    }
}

/// The playback fields a smart playlist needs, decoupled from the persisted
/// `PlaybackState` model.
public struct SmartPlaylistPlayback: Equatable, Sendable {
    /// Current playback position in seconds.
    public var position: Double
    /// Media duration in seconds.
    public var duration: Double
    /// Whether playback has reached the app's finished threshold.
    public var isFinished: Bool
    /// Number of completed plays.
    public var playCount: Int
    /// Last time the item was played, if it has ever been played.
    public var lastPlayedAt: Date?

    public init(
        position: Double = 0,
        duration: Double = 0,
        isFinished: Bool = false,
        playCount: Int = 0,
        lastPlayedAt: Date? = nil
    ) {
        self.position = position
        self.duration = duration
        self.isFinished = isFinished
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
    }
}

/// A lightweight, value-type snapshot of one library item for smart playlist
/// evaluation. Keeping this independent of SwiftData lets the engine be tested
/// and reused without a model container.
public struct SmartPlaylistEntry: Identifiable, Equatable, Sendable {
    /// The underlying media item's ID.
    public let id: UUID
    /// When the item was added to the library.
    public var addedAt: Date
    /// The item's collection, if any.
    public var collectionID: UUID?
    /// Missing items stay in the library database but never appear in smart
    /// playlists.
    public var isMissing: Bool
    /// The item's playback state, if it has ever been played or saved.
    public var playback: SmartPlaylistPlayback?

    public init(
        id: UUID,
        addedAt: Date,
        collectionID: UUID? = nil,
        isMissing: Bool = false,
        playback: SmartPlaylistPlayback? = nil
    ) {
        self.id = id
        self.addedAt = addedAt
        self.collectionID = collectionID
        self.isMissing = isMissing
        self.playback = playback
    }
}

/// Computes smart playlist membership and ordering from entry snapshots.
///
/// Shared filtering rules:
/// - Missing entries (`isMissing == true`) are excluded from every kind.
/// - When `collectionID` is non-nil, only entries belonging to that collection
///   remain. A nil `collectionID` means "no collection filter"; it does not
///   select items that have no collection.
///
/// Predicates:
/// - ``SmartPlaylistKind/continueListening`` and ``SmartPlaylistKind/unfinished``:
///   playback exists, is not finished, has a positive play count, and has a
///   finite position greater than zero. These kinds intentionally share one
///   predicate; "continue listening" is the short recent view and "unfinished"
///   is the full list.
/// - ``SmartPlaylistKind/recentlyAdded``: `addedAt >= now - max(0,
///   recentWindow)`. The exact boundary is included, future dates are included,
///   and missing playback does not matter.
/// - ``SmartPlaylistKind/finished``: `playback?.isFinished == true`, regardless
///   of position, duration, or play count.
///
/// Ordering is deterministic:
/// - Continue listening and unfinished: `lastPlayedAt` descending, then
///   `addedAt` descending, then `id.uuidString` ascending.
/// - Recently added: `addedAt` descending, then `id.uuidString` ascending.
/// - Finished: `lastPlayedAt` descending, then `addedAt` descending, then
///   `id.uuidString` ascending.
///
/// Entries without a valid `lastPlayedAt` sort after entries that have one. A
/// non-finite date is treated as absent for ordering, and a non-finite
/// `position` can never satisfy the in-progress predicate. `limit` is applied
/// after filtering and sorting: nil means unlimited, and a non-positive limit
/// returns an empty list.
public enum SmartPlaylistEngine {
    /// The default "recently added" window: 30 days.
    public static let defaultRecentWindow: TimeInterval = 30 * 24 * 60 * 60

    /// Returns the entries in a smart playlist, filtered, ordered, and limited.
    ///
    /// - Parameters:
    ///   - entries: The library snapshots to evaluate.
    ///   - kind: Which smart playlist to build.
    ///   - collectionID: When non-nil, restrict results to that collection.
    ///   - now: Reference time for the recently-added window and for callers
    ///     that want reproducible results.
    ///   - recentWindow: Lookback interval for ``SmartPlaylistKind/recentlyAdded``.
    ///     Negative values are clamped to zero.
    ///   - limit: Maximum number of rows to return after filtering and sorting.
    ///     nil returns every match; zero or a negative value returns no rows.
    public static func entries(
        _ entries: [SmartPlaylistEntry],
        kind: SmartPlaylistKind,
        collectionID: UUID? = nil,
        now: Date = Date(),
        recentWindow: TimeInterval = defaultRecentWindow,
        limit: Int? = nil
    ) -> [SmartPlaylistEntry] {
        var result = candidates(entries, collectionID: collectionID).filter {
            matches($0, kind: kind, now: now, recentWindow: recentWindow)
        }

        switch kind {
        case .continueListening, .unfinished, .finished:
            result.sort(by: playbackOrderedBefore)
        case .recentlyAdded:
            result.sort(by: recentOrderedBefore)
        }

        guard let limit else { return result }
        guard limit > 0 else { return [] }
        return Array(result.prefix(limit))
    }

    /// Counts each smart playlist using the same predicates and filters as
    /// ``entries(_:kind:collectionID:now:recentWindow:limit:)`` but without a
    /// limit. Every kind is present in the result, including kinds with zero
    /// matches.
    public static func counts(
        _ entries: [SmartPlaylistEntry],
        collectionID: UUID? = nil,
        now: Date = Date(),
        recentWindow: TimeInterval = defaultRecentWindow
    ) -> [SmartPlaylistKind: Int] {
        let eligible = candidates(entries, collectionID: collectionID)
        var result: [SmartPlaylistKind: Int] = [:]
        for kind in SmartPlaylistKind.allCases {
            result[kind] = eligible.filter {
                matches($0, kind: kind, now: now, recentWindow: recentWindow)
            }.count
        }
        return result
    }

    // MARK: - Filtering

    private static func candidates(
        _ entries: [SmartPlaylistEntry],
        collectionID: UUID?
    ) -> [SmartPlaylistEntry] {
        entries.filter { entry in
            guard !entry.isMissing else { return false }
            guard let collectionID else { return true }
            return entry.collectionID == collectionID
        }
    }

    private static func matches(
        _ entry: SmartPlaylistEntry,
        kind: SmartPlaylistKind,
        now: Date,
        recentWindow: TimeInterval
    ) -> Bool {
        switch kind {
        case .continueListening, .unfinished:
            guard let playback = entry.playback else { return false }
            return !playback.isFinished
                && playback.playCount > 0
                && playback.position.isFinite
                && playback.position > 0

        case .recentlyAdded:
            guard isValid(entry.addedAt) else { return false }
            let window = max(0, recentWindow)
            let cutoff = now.addingTimeInterval(-window)
            return entry.addedAt >= cutoff

        case .finished:
            return entry.playback?.isFinished == true
        }
    }

    // MARK: - Ordering

    private static func playbackOrderedBefore(
        _ lhs: SmartPlaylistEntry,
        _ rhs: SmartPlaylistEntry
    ) -> Bool {
        if let ordered = descendingOrder(
            validDate(lhs.playback?.lastPlayedAt),
            validDate(rhs.playback?.lastPlayedAt)
        ) {
            return ordered
        }
        if let ordered = descendingOrder(validDate(lhs.addedAt), validDate(rhs.addedAt)) {
            return ordered
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func recentOrderedBefore(
        _ lhs: SmartPlaylistEntry,
        _ rhs: SmartPlaylistEntry
    ) -> Bool {
        if let ordered = descendingOrder(validDate(lhs.addedAt), validDate(rhs.addedAt)) {
            return ordered
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Compares two optional dates for descending order, with nil after every
    /// non-nil date. Returns nil when the dates tie.
    private static func descendingOrder(_ lhs: Date?, _ rhs: Date?) -> Bool? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case (nil, _):
            return false
        case (_, nil):
            return true
        case let (lhs?, rhs?):
            if lhs == rhs { return nil }
            return lhs > rhs
        }
    }

    /// Dates built from NaN or infinite intervals are not usable for ordering
    /// and are treated like a missing date.
    private static func validDate(_ date: Date?) -> Date? {
        guard let date, date.timeIntervalSinceReferenceDate.isFinite else {
            return nil
        }
        return date
    }

    private static func isValid(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }
}
