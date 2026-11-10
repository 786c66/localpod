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

public enum LocalPodMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [LocalPodSchemaV1.self, LocalPodSchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    public static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: LocalPodSchemaV1.self,
        toVersion: LocalPodSchemaV2.self
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
        let schema = Schema(versionedSchema: LocalPodSchemaV2.self)
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
