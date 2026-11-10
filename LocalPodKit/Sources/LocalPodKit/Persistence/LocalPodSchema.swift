import Foundation
import SwiftData

public enum LocalPodSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [MediaItem.self]
    }
}

public enum LocalPodMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [LocalPodSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
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

    /// M0 keeps the schema versioned from day one so later migrations have a
    /// real starting point. The store lives under Application Support by default.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LocalPodSchemaV1.self)
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
