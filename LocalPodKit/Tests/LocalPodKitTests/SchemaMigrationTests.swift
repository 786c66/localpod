import Foundation
import SwiftData
import XCTest
@testable import LocalPodKit

@MainActor
final class SchemaMigrationTests: XCTestCase {
    func testV1StoreMigratesToV3() throws {
        let root = try TemporaryDirectory()
        let storeURL = root.url.appendingPathComponent("LocalPod.store")

        try makeV1Store(at: storeURL)

        let container = try openV3Store(at: storeURL)
        let context = container.mainContext
        let items = try context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.title, "M0 item")
        XCTAssertEqual(item.relativePath, "Media/m0.m4a")
        XCTAssertNil(item.fingerprint)
        XCTAssertFalse(item.isMissing)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MediaCollection>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ImportSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlaybackState>()), 0)

        context.insert(PlaybackState(itemID: item.id, position: 42, duration: 300))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlaybackState>()), 1)
    }

    func testV2StoreMigratesToV3AndKeepsData() throws {
        let root = try TemporaryDirectory()
        let storeURL = root.url.appendingPathComponent("LocalPod.store")

        try makeV2Store(at: storeURL)

        let container = try openV3Store(at: storeURL)
        let context = container.mainContext
        let items = try context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.title, "M1 item")
        XCTAssertEqual(item.fingerprint, "abc123")
        XCTAssertEqual(item.artworkKey, "artwork.jpg")

        let collections = try context.fetch(FetchDescriptor<MediaCollection>())
        XCTAssertEqual(collections.count, 1)
        XCTAssertEqual(collections.first?.name, "M1 合集")
        XCTAssertEqual(item.collectionID, collections.first?.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlaybackState>()), 0)

        context.insert(PlaybackState(
            itemID: item.id,
            position: 12,
            duration: 60,
            playCount: 1
        ))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlaybackState>()), 1)
    }

    private func openV3Store(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LocalPodSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: LocalPodMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private func makeV2Store(at url: URL) throws {
        let schema = Schema(versionedSchema: LocalPodSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
        let context = container.mainContext
        let collection = LocalPodSchemaV2.MediaCollection(
            name: "M1 合集",
            nameKey: "m1 合集",
            lastImportedAt: Date()
        )
        context.insert(collection)
        context.insert(LocalPodSchemaV2.MediaItem(
            title: "M1 item",
            relativePath: "Media/m1.m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 456,
            durationSeconds: 60,
            folderName: "M1 合集",
            fingerprint: "abc123",
            collectionID: collection.id,
            artworkKey: "artwork.jpg"
        ))
        try context.save()
    }

    private func makeV1Store(at url: URL) throws {
        let schema = Schema(versionedSchema: LocalPodSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
        let context = container.mainContext
        context.insert(LocalPodSchemaV1.MediaItem(
            title: "M0 item",
            relativePath: "Media/m0.m4a",
            kind: .audio,
            fileExtension: "m4a",
            byteSize: 123,
            folderName: "M0"
        ))
        try context.save()
    }
}
