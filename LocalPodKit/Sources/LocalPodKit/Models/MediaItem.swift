import Foundation
import SwiftData

public enum MediaSource: String, Codable, Sendable {
    case imported
    case benchmark
}

@Model
public final class MediaItem {
    public var id: UUID = UUID()
    public var title: String = ""
    /// Path relative to Application Support. Never store an absolute container path.
    public var relativePath: String = ""
    public var kindRaw: String = MediaKind.audio.rawValue
    public var fileExtension: String = ""
    public var byteSize: Int64 = 0
    public var durationSeconds: Double?
    public var addedAt: Date = Date()
    public var folderName: String?
    public var sourceRaw: String = MediaSource.imported.rawValue
    public var contentHash: String?

    public init(
        id: UUID = UUID(),
        title: String,
        relativePath: String,
        kind: MediaKind,
        fileExtension: String,
        byteSize: Int64,
        durationSeconds: Double? = nil,
        addedAt: Date = Date(),
        folderName: String? = nil,
        source: MediaSource = .imported,
        contentHash: String? = nil
    ) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
        self.kindRaw = kind.rawValue
        self.fileExtension = fileExtension
        self.byteSize = byteSize
        self.durationSeconds = durationSeconds
        self.addedAt = addedAt
        self.folderName = folderName
        self.sourceRaw = source.rawValue
        self.contentHash = contentHash
    }

    public var kind: MediaKind {
        get { MediaKind(rawValue: kindRaw) ?? .audio }
        set { kindRaw = newValue.rawValue }
    }

    public var source: MediaSource {
        get { MediaSource(rawValue: sourceRaw) ?? .imported }
        set { sourceRaw = newValue.rawValue }
    }

    public var fileURL: URL? {
        try? MediaStorage.live.url(forRelativePath: relativePath)
    }
}
