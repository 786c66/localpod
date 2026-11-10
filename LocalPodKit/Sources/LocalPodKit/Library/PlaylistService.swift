import Foundation
import SwiftData

/// CRUD and ordering for user playlists. Views normally read rows through
/// `@Query`; this service is the single write path so ordering and cleanup stay
/// consistent.
@MainActor
public final class PlaylistService {
    public static let defaultName = "新建播放列表"

    @ObservationIgnored private var context: ModelContext?

    public init(context: ModelContext? = nil) {
        self.context = context
    }

    public func attach(context: ModelContext) {
        self.context = context
    }

    // MARK: - Read

    public func allPlaylists() -> [Playlist] {
        guard let context else { return [] }
        return (try? context.fetch(FetchDescriptor<Playlist>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))) ?? []
    }

    public func entries(in playlist: Playlist) -> [PlaylistEntry] {
        guard let context else { return [] }
        let playlistID = playlist.id
        let descriptor = FetchDescriptor<PlaylistEntry>(
            predicate: #Predicate { $0.playlistID == playlistID },
            sortBy: [SortDescriptor(\.position)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public func itemIDs(in playlist: Playlist) -> [UUID] {
        entries(in: playlist).map(\.itemID)
    }

    public func count(in playlist: Playlist) -> Int {
        entries(in: playlist).count
    }

    public func contains(itemID: UUID, in playlist: Playlist) -> Bool {
        entries(in: playlist).contains { $0.itemID == itemID }
    }

    // MARK: - Playlist CRUD

    @discardableResult
    public func create(name: String) -> Playlist? {
        guard let context else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let existing = allPlaylists()
        let playlist = Playlist(
            name: trimmed,
            sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(playlist)
        try? context.save()
        return playlist
    }

    @discardableResult
    public func rename(_ playlist: Playlist, to name: String) -> Bool {
        guard let context else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        playlist.name = trimmed
        playlist.updatedAt = Date()
        try? context.save()
        return true
    }

    public func delete(_ playlist: Playlist) {
        guard let context else { return }
        for entry in entries(in: playlist) {
            context.delete(entry)
        }
        context.delete(playlist)
        try? context.save()
    }

    // MARK: - Entries

    /// Adds an item at the end. Returns false when the playlist already has it.
    @discardableResult
    public func add(itemID: UUID, to playlist: Playlist) -> Bool {
        guard let context else { return false }
        let existing = entries(in: playlist)
        guard !existing.contains(where: { $0.itemID == itemID }) else {
            return false
        }
        context.insert(PlaylistEntry(
            playlistID: playlist.id,
            itemID: itemID,
            position: (existing.map(\.position).max() ?? -1) + 1
        ))
        playlist.updatedAt = Date()
        try? context.save()
        return true
    }

    public func add(itemIDs: [UUID], to playlist: Playlist) {
        for itemID in itemIDs {
            add(itemID: itemID, to: playlist)
        }
    }

    @discardableResult
    public func remove(itemID: UUID, from playlist: Playlist) -> Bool {
        guard let context else { return false }
        let matches = entries(in: playlist).filter { $0.itemID == itemID }
        guard !matches.isEmpty else { return false }
        for entry in matches {
            context.delete(entry)
        }
        normalizePositions(in: playlist)
        playlist.updatedAt = Date()
        try? context.save()
        return true
    }

    @discardableResult
    public func removeEntry(id: UUID) -> Bool {
        guard let context else { return false }
        var descriptor = FetchDescriptor<PlaylistEntry>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let entry = try? context.fetch(descriptor).first else { return false }
        let playlistID = entry.playlistID
        context.delete(entry)
        if let playlist = playlist(withID: playlistID) {
            normalizePositions(in: playlist)
            playlist.updatedAt = Date()
        }
        try? context.save()
        return true
    }

    public func move(
        in playlist: Playlist,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        guard let context else { return }
        var rows = entries(in: playlist)
        rows.moveElements(fromOffsets: source, toOffset: destination)
        for (index, row) in rows.enumerated() {
            row.position = index
        }
        playlist.updatedAt = Date()
        try? context.save()
    }

    /// Removes playlist membership when a library item is deleted.
    public func removeAllEntries(forItemID itemID: UUID) {
        guard let context else { return }
        let descriptor = FetchDescriptor<PlaylistEntry>(
            predicate: #Predicate { $0.itemID == itemID }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        let playlistIDs = Set(rows.map(\.playlistID))
        for row in rows {
            context.delete(row)
        }
        for playlistID in playlistIDs {
            if let playlist = playlist(withID: playlistID) {
                normalizePositions(in: playlist)
                playlist.updatedAt = Date()
            }
        }
        try? context.save()
    }

    // MARK: - Helpers

    private func playlist(withID id: UUID) -> Playlist? {
        guard let context else { return nil }
        var descriptor = FetchDescriptor<Playlist>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func normalizePositions(in playlist: Playlist) {
        for (index, entry) in entries(in: playlist).enumerated() {
            entry.position = index
        }
    }
}
