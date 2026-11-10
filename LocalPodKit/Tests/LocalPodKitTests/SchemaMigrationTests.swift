import Foundation
import SwiftData
import XCTest
@testable import LocalPodKit

@MainActor
final class SchemaMigrationTests: XCTestCase {
    func testV1StoreMigratesToV2() throws {
        let root = try TemporaryDirectory()
        let storeURL = root.url.appendingPathComponent("LocalPod.store")

        try makeV1Store(at: storeURL)

        let schema = Schema(versionedSchema: LocalPodSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: LocalPodMigrationPlan.self,
            configurations: [configuration]
        )
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
