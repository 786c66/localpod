import Foundation
import SwiftData

public enum MediaSource: String, Codable, Sendable, CaseIterable {
    case imported
    case files
    case iCloud
    case openIn
    case finder
    case wifi
    case share
    case rss
    case benchmark
    case sample

    public var displayName: String {
        switch self {
        case .imported: "导入"
        case .files: "文件"
        case .iCloud: "iCloud Drive"
        case .openIn: "外部打开"
        case .finder: "Finder"
        case .wifi: "Wi-Fi"
        case .share: "分享"
        case .rss: "RSS"
        case .benchmark: "基准"
        case .sample: "示例"
        }
    }
}

public typealias MediaItem = LocalPodSchemaV2.MediaItem
public typealias MediaCollection = LocalPodSchemaV2.MediaCollection
public typealias ImportSession = LocalPodSchemaV2.ImportSession
public typealias PlaybackState = LocalPodSchemaV3.PlaybackState
public typealias QueueEntry = LocalPodSchemaV4.QueueEntry
public typealias QueueState = LocalPodSchemaV4.QueueState
public typealias Playlist = LocalPodSchemaV4.Playlist
public typealias PlaylistEntry = LocalPodSchemaV4.PlaylistEntry

public extension LocalPodSchemaV2.MediaItem {
    var kind: MediaKind {
        get { MediaKind(rawValue: kindRaw) ?? .audio }
        set { kindRaw = newValue.rawValue }
    }

    var source: MediaSource {
        get { MediaSource(rawValue: sourceRaw) ?? .imported }
        set { sourceRaw = newValue.rawValue }
    }

    var fileSize: Int64 {
        get { byteSize }
        set { byteSize = newValue }
    }

    var fileURL: URL? {
        try? MediaStorage.live.url(forRelativePath: relativePath)
    }

    var artworkURL: URL? {
        guard let artworkKey else { return nil }
        return try? MediaStorage.live.artworkURL(forKey: artworkKey)
    }

    var durationText: String {
        guard let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 else {
            return "—"
        }
        let total = Int(durationSeconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

public extension LocalPodSchemaV2.MediaCollection {
    static func normalizedKey(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
