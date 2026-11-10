import Foundation

public struct PlaybackItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let fileURL: URL
    public let kind: MediaKind
    public let durationHint: Double?

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        fileURL: URL,
        kind: MediaKind,
        durationHint: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.fileURL = fileURL
        self.kind = kind
        self.durationHint = durationHint
    }
}
