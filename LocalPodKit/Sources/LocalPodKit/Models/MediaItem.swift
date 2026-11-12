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
        displayName(locale: nil)
    }

    /// Resolve the source label against an explicit locale. Passing `nil` uses
    /// the process/language environment, which is what the app displays.
    public func displayName(locale: Locale?) -> String {
        switch self {
        case .imported: LocalPodLocalization.string("source.imported", locale: locale)
        case .files: LocalPodLocalization.string("source.files", locale: locale)
        case .iCloud: LocalPodLocalization.string("source.iCloud", locale: locale)
        case .openIn: LocalPodLocalization.string("source.openIn", locale: locale)
        case .finder: LocalPodLocalization.string("source.finder", locale: locale)
        case .wifi: LocalPodLocalization.string("source.wifi", locale: locale)
        case .share: LocalPodLocalization.string("source.share", locale: locale)
        case .rss: LocalPodLocalization.string("source.rss", locale: locale)
        case .benchmark: LocalPodLocalization.string("source.benchmark", locale: locale)
        case .sample: LocalPodLocalization.string("source.sample", locale: locale)
        }
    }
}

public typealias MediaItem = LocalPodSchemaV7.MediaItem
public typealias MediaCollection = LocalPodSchemaV7.MediaCollection
public typealias ImportSession = LocalPodSchemaV2.ImportSession
public typealias PlaybackState = LocalPodSchemaV3.PlaybackState
public typealias QueueEntry = LocalPodSchemaV4.QueueEntry
public typealias QueueState = LocalPodSchemaV4.QueueState
public typealias Playlist = LocalPodSchemaV4.Playlist
public typealias PlaylistEntry = LocalPodSchemaV4.PlaylistEntry
public typealias LinkedFolder = LocalPodSchemaV5.LinkedFolder
public typealias TrashItem = LocalPodSchemaV6.TrashItem

public extension LocalPodSchemaV7.MediaItem {
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

public extension LocalPodSchemaV7.MediaCollection {
    static func normalizedKey(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var sortMode: CollectionSortMode {
        get { CollectionSortMode(rawValue: sortModeRaw) ?? .natural }
        set { sortModeRaw = newValue.rawValue }
    }
}

public extension LocalPodSchemaV7.MediaItem {
    /// Source-relative path of a linked item inside its linked folder.
    var linkedSourceRelativePath: String {
        if relativeFolderPath.isEmpty {
            return originalFileName
        }
        return "\(relativeFolderPath)/\(originalFileName)"
    }
}
