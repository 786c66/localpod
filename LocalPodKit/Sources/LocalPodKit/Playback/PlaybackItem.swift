import Foundation

public struct PlaybackItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let fileURL: URL
    public let kind: MediaKind
    public let durationHint: Double?
    /// `MediaItem.id` for library media. Nil for bundled demo clips; when nil
    /// playback progress is not persisted.
    public let libraryItemID: UUID?
    public let artworkURL: URL?
    /// Embedded chapters carried for context (queue hand-offs, future backup);
    /// live playback chapters live on the controller.
    public var chapters: [ChapterInfo] = []

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        fileURL: URL,
        kind: MediaKind,
        durationHint: Double? = nil,
        libraryItemID: UUID? = nil,
        artworkURL: URL? = nil,
        chapters: [ChapterInfo] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.fileURL = fileURL
        self.kind = kind
        self.durationHint = durationHint
        self.libraryItemID = libraryItemID
        self.artworkURL = artworkURL
        self.chapters = chapters
    }
}
