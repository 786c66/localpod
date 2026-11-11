import Foundation
import SwiftData

/// Snapshot of the M0 schema. Kept so the M1 data model can be reached with a
/// real lightweight migration instead of silently changing a shipped schema.
public enum LocalPodSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [MediaItem.self]
    }

    @Model
    public final class MediaItem {
        public var id: UUID = UUID()
        public var title: String = ""
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
    }
}

public enum LocalPodSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [MediaItem.self, MediaCollection.self, ImportSession.self]
    }

    @Model
    public final class MediaItem {
        public var id: UUID = UUID()
        public var title: String = ""
        public var sortTitle: String = ""
        public var originalFileName: String = ""
        /// Path relative to Application Support. Never store an absolute container path.
        public var relativePath: String = ""
        /// Path inside the imported folder, e.g. "Season 1/Disc 1".
        public var relativeFolderPath: String = ""
        public var kindRaw: String = MediaKind.audio.rawValue
        public var fileExtension: String = ""
        public var byteSize: Int64 = 0
        public var durationSeconds: Double?
        public var addedAt: Date = Date()
        public var folderName: String?
        public var sourceRaw: String = MediaSource.imported.rawValue
        public var sourceName: String?
        /// SHA-256 of the file contents. Used for deduplication and relinking.
        public var fingerprint: String?
        public var collectionID: UUID?
        public var artworkKey: String?
        public var importSessionID: UUID?
        public var isMissing: Bool = false
        public var isFavorite: Bool = false
        public var notes: String?

        public init(
            id: UUID = UUID(),
            title: String,
            sortTitle: String? = nil,
            originalFileName: String = "",
            relativePath: String,
            relativeFolderPath: String = "",
            kind: MediaKind,
            fileExtension: String,
            byteSize: Int64,
            durationSeconds: Double? = nil,
            addedAt: Date = Date(),
            folderName: String? = nil,
            source: MediaSource = .imported,
            sourceName: String? = nil,
            fingerprint: String? = nil,
            collectionID: UUID? = nil,
            artworkKey: String? = nil,
            importSessionID: UUID? = nil,
            isMissing: Bool = false,
            isFavorite: Bool = false,
            notes: String? = nil
        ) {
            self.id = id
            self.title = title
            self.sortTitle = sortTitle ?? title
            self.originalFileName = originalFileName
            self.relativePath = relativePath
            self.relativeFolderPath = relativeFolderPath
            self.kindRaw = kind.rawValue
            self.fileExtension = fileExtension
            self.byteSize = byteSize
            self.durationSeconds = durationSeconds
            self.addedAt = addedAt
            self.folderName = folderName
            self.sourceRaw = source.rawValue
            self.sourceName = sourceName
            self.fingerprint = fingerprint
            self.collectionID = collectionID
            self.artworkKey = artworkKey
            self.importSessionID = importSessionID
            self.isMissing = isMissing
            self.isFavorite = isFavorite
            self.notes = notes
        }
    }

    @Model
    public final class MediaCollection {
        public var id: UUID = UUID()
        public var name: String = ""
        public var nameKey: String = ""
        public var createdAt: Date = Date()
        public var sortOrder: Int = 0
        public var lastImportedAt: Date = Date()

        public init(
            id: UUID = UUID(),
            name: String,
            nameKey: String,
            createdAt: Date = Date(),
            sortOrder: Int = 0,
            lastImportedAt: Date = Date()
        ) {
            self.id = id
            self.name = name
            self.nameKey = nameKey
            self.createdAt = createdAt
            self.sortOrder = sortOrder
            self.lastImportedAt = lastImportedAt
        }
    }

    @Model
    public final class ImportSession {
        public var id: UUID = UUID()
        public var startedAt: Date = Date()
        public var endedAt: Date = Date()
        public var sourceRaw: String = MediaSource.files.rawValue
        public var rootName: String = ""
        public var totalCandidates: Int = 0
        public var supportedFiles: Int = 0
        public var totalBytes: Int64 = 0
        public var importedCount: Int = 0
        public var duplicateCount: Int = 0
        public var unsupportedCount: Int = 0
        public var failedCount: Int = 0
        public var relinkedCount: Int = 0
        public var cancelled: Bool = false
        public var reportPath: String?
        public var statusRaw: String = ImportSessionStatus.finished.rawValue

        public init(
            id: UUID = UUID(),
            startedAt: Date,
            endedAt: Date,
            source: MediaSource,
            rootName: String,
            totalCandidates: Int,
            supportedFiles: Int,
            totalBytes: Int64,
            importedCount: Int,
            duplicateCount: Int,
            unsupportedCount: Int,
            failedCount: Int,
            relinkedCount: Int,
            cancelled: Bool,
            reportPath: String?,
            status: ImportSessionStatus
        ) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.sourceRaw = source.rawValue
            self.rootName = rootName
            self.totalCandidates = totalCandidates
            self.supportedFiles = supportedFiles
            self.totalBytes = totalBytes
            self.importedCount = importedCount
            self.duplicateCount = duplicateCount
            self.unsupportedCount = unsupportedCount
            self.failedCount = failedCount
            self.relinkedCount = relinkedCount
            self.cancelled = cancelled
            self.reportPath = reportPath
            self.statusRaw = status.rawValue
        }
    }
}

public enum ImportSessionStatus: String, Codable, Sendable {
    case finished
    case cancelled
    case failed
}

/// M2 adds a small, independent playback-state table so periodic progress
/// writes never invalidate MediaItem rows (and therefore the library list).
/// The unchanged V2 entities are reused across schema versions.
public enum LocalPodSchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            LocalPodSchemaV2.MediaItem.self,
            LocalPodSchemaV2.MediaCollection.self,
            LocalPodSchemaV2.ImportSession.self,
            PlaybackState.self
        ]
    }

    @Model
    public final class PlaybackState {
        @Attribute(.unique) public var itemID: UUID = UUID()
        /// Seconds. Saved about once per second while playing, plus on
        /// pause/seek/background/item switch.
        public var position: Double = 0
        /// Player-reported duration; falls back to the imported duration.
        public var duration: Double = 0
        public var isFinished: Bool = false
        public var playCount: Int = 0
        public var lastPlayedAt: Date?
        public var updatedAt: Date = Date()

        public init(
            itemID: UUID,
            position: Double = 0,
            duration: Double = 0,
            isFinished: Bool = false,
            playCount: Int = 0,
            lastPlayedAt: Date? = nil,
            updatedAt: Date = Date()
        ) {
            self.itemID = itemID
            self.position = position
            self.duration = duration
            self.isFinished = isFinished
            self.playCount = playCount
            self.lastPlayedAt = lastPlayedAt
            self.updatedAt = updatedAt
        }
    }
}

public enum QueueRepeatMode: String, CaseIterable, Codable, Sendable {
    case off
    case all
    case one

    public var displayName: String {
        displayName(locale: nil)
    }

    public func displayName(locale: Locale?) -> String {
        switch self {
        case .off: LocalPodLocalization.string("queue.repeat.off", locale: locale)
        case .all: LocalPodLocalization.string("queue.repeat.all", locale: locale)
        case .one: LocalPodLocalization.string("queue.repeat.one", locale: locale)
        }
    }

    public var symbolName: String {
        switch self {
        case .off: "repeat"
        case .all: "repeat"
        case .one: "repeat.1"
        }
    }
}

/// M3 adds the ordered playback queue, its small singleton state row, and
/// user-created playlists. All previous entities are reused unchanged.
public enum LocalPodSchemaV4: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            LocalPodSchemaV2.MediaItem.self,
            LocalPodSchemaV2.MediaCollection.self,
            LocalPodSchemaV2.ImportSession.self,
            LocalPodSchemaV3.PlaybackState.self,
            QueueEntry.self,
            QueueState.self,
            Playlist.self,
            PlaylistEntry.self
        ]
    }

    @Model
    public final class QueueEntry {
        @Attribute(.unique) public var id: UUID = UUID()
        public var itemID: UUID = UUID()
        public var position: Int = 0

        public init(id: UUID = UUID(), itemID: UUID, position: Int) {
            self.id = id
            self.itemID = itemID
            self.position = position
        }
    }

    @Model
    public final class QueueState {
        @Attribute(.unique) public var key: String = "main"
        public var currentItemID: UUID?
        public var shuffleEnabled: Bool = false
        /// Repeat mode raw value. Kept as a string so future modes can migrate
        /// without changing the stored schema type.
        public var repeatModeRaw: String = QueueRepeatMode.off.rawValue
        /// Comma-separated UUIDs describing the current shuffle play order.
        /// Empty when shuffle is off.
        public var shuffleOrderRaw: String = ""
        public var updatedAt: Date = Date()

        public init(
            key: String = "main",
            currentItemID: UUID? = nil,
            shuffleEnabled: Bool = false,
            repeatMode: QueueRepeatMode = .off,
            shuffleOrder: [UUID] = [],
            updatedAt: Date = Date()
        ) {
            self.key = key
            self.currentItemID = currentItemID
            self.shuffleEnabled = shuffleEnabled
            self.repeatModeRaw = repeatMode.rawValue
            self.shuffleOrderRaw = shuffleOrder.map(\.uuidString).joined(separator: ",")
            self.updatedAt = updatedAt
        }
    }

    @Model
    public final class Playlist {
        @Attribute(.unique) public var id: UUID = UUID()
        public var name: String = ""
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var sortOrder: Int = 0

        public init(
            id: UUID = UUID(),
            name: String,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            sortOrder: Int = 0
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.sortOrder = sortOrder
        }
    }

    @Model
    public final class PlaylistEntry {
        @Attribute(.unique) public var id: UUID = UUID()
        public var playlistID: UUID = UUID()
        public var itemID: UUID = UUID()
        public var position: Int = 0

        public init(
            id: UUID = UUID(),
            playlistID: UUID,
            itemID: UUID,
            position: Int
        ) {
            self.id = id
            self.playlistID = playlistID
            self.itemID = itemID
            self.position = position
        }
    }
}

/// P2 "链接文件夹" adds the linked-folder registry. Rows hold only a
/// security-scoped bookmark (never an absolute path) plus scan bookkeeping.
/// All previous entities are reused unchanged.
public enum LocalPodSchemaV5: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            LocalPodSchemaV2.MediaItem.self,
            LocalPodSchemaV2.MediaCollection.self,
            LocalPodSchemaV2.ImportSession.self,
            LocalPodSchemaV3.PlaybackState.self,
            LocalPodSchemaV4.QueueEntry.self,
            LocalPodSchemaV4.QueueState.self,
            LocalPodSchemaV4.Playlist.self,
            LocalPodSchemaV4.PlaylistEntry.self,
            LinkedFolder.self
        ]
    }

    @Model
    public final class LinkedFolder: Hashable, Identifiable {
        @Attribute(.unique) public var id: UUID = UUID()
        /// Security-scoped bookmark of the linked source folder. Bookmarks are
        /// stable across container-path changes; absolute paths are never stored.
        public var bookmarkData: Data = Data()
        /// Display name and import attribution key (folder name at link time).
        public var rootName: String = ""
        public var addedAt: Date = Date()
        /// Last completed (not cancelled) rescan. `nil` until the first sync.
        public var lastScannedAt: Date?
        /// Files imported by the last completed rescan.
        public var lastImportedCount: Int = 0
        /// Files that disappeared from the source in the last rescan. Local
        /// copies are intentionally kept; this count is informational only.
        public var lastRemovedCount: Int = 0
        /// True when the bookmark could not be resolved (folder moved,
        /// renamed, or deleted). The user must re-pick the folder.
        public var isStale: Bool = false
        /// Reserved for a future "pause this link" toggle.
        public var enabled: Bool = true

        public init(
            id: UUID = UUID(),
            bookmarkData: Data,
            rootName: String,
            addedAt: Date = Date(),
            lastScannedAt: Date? = nil,
            lastImportedCount: Int = 0,
            lastRemovedCount: Int = 0,
            isStale: Bool = false,
            enabled: Bool = true
        ) {
            self.id = id
            self.bookmarkData = bookmarkData
            self.rootName = rootName
            self.addedAt = addedAt
            self.lastScannedAt = lastScannedAt
            self.lastImportedCount = lastImportedCount
            self.lastRemovedCount = lastRemovedCount
            self.isStale = isStale
            self.enabled = enabled
        }
    }
}

public enum LocalPodMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [
            LocalPodSchemaV1.self,
            LocalPodSchemaV2.self,
            LocalPodSchemaV3.self,
            LocalPodSchemaV4.self,
            LocalPodSchemaV5.self
        ]
    }

    public static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5]
    }

    public static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: LocalPodSchemaV1.self,
        toVersion: LocalPodSchemaV2.self
    )

    public static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: LocalPodSchemaV2.self,
        toVersion: LocalPodSchemaV3.self
    )

    public static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: LocalPodSchemaV3.self,
        toVersion: LocalPodSchemaV4.self
    )

    public static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: LocalPodSchemaV4.self,
        toVersion: LocalPodSchemaV5.self
    )
}

public enum LocalPodStore {
    /// Debug/testing helper. Only call before creating the ModelContainer.
    public static func deleteDefaultStoreFiles() {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return
        }
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            try? FileManager.default.removeItem(at: support.appendingPathComponent(name))
        }
    }

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LocalPodSchemaV5.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: LocalPodMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
