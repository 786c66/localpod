import XCTest
@testable import LocalPodKit

@MainActor
final class AppSettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let prefix = "localpod.test.settings."

    override func setUp() async throws {
        suiteName = "LocalPodTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testDefaults() {
        let store = AppSettingsStore(defaults: defaults, keyPrefix: prefix)
        XCTAssertEqual(store.defaultRate, 1.0, accuracy: 0.001)
        XCTAssertEqual(store.skipForwardSeconds, 15)
        XCTAssertEqual(store.skipBackwardSeconds, 15)
        XCTAssertTrue(store.resumeEnabled)
        XCTAssertTrue(store.autoPlayNext)
        XCTAssertTrue(store.signingReminderEnabled)
        XCTAssertFalse(store.importNotificationsEnabled)
    }

    func testValuesPersistForANewStore() {
        let store = AppSettingsStore(defaults: defaults, keyPrefix: prefix)
        store.defaultRate = 1.5
        store.skipForwardSeconds = 30
        store.skipBackwardSeconds = 10
        store.resumeEnabled = false
        store.autoPlayNext = false
        store.signingReminderEnabled = false
        store.importNotificationsEnabled = true

        let restored = AppSettingsStore(defaults: defaults, keyPrefix: prefix)
        XCTAssertEqual(restored.defaultRate, 1.5, accuracy: 0.001)
        XCTAssertEqual(restored.skipForwardSeconds, 30)
        XCTAssertEqual(restored.skipBackwardSeconds, 10)
        XCTAssertFalse(restored.resumeEnabled)
        XCTAssertFalse(restored.autoPlayNext)
        XCTAssertFalse(restored.signingReminderEnabled)
        XCTAssertTrue(restored.importNotificationsEnabled)
    }

    func testStoredOutOfRangeValuesAreClamped() {
        defaults.set(9.0, forKey: prefix + AppSettingsStore.keyDefaultRate)
        defaults.set(1.0, forKey: prefix + AppSettingsStore.keySkipForward)
        defaults.set(999.0, forKey: prefix + AppSettingsStore.keySkipBackward)

        let store = AppSettingsStore(defaults: defaults, keyPrefix: prefix)
        XCTAssertEqual(store.defaultRate, 3.0, accuracy: 0.001)
        XCTAssertEqual(store.skipForwardSeconds, 5)
        XCTAssertEqual(store.skipBackwardSeconds, 120)
    }

    func testResetAndClearStoredValues() {
        let store = AppSettingsStore(defaults: defaults, keyPrefix: prefix)
        store.defaultRate = 2.0
        store.skipForwardSeconds = 45
        store.resumeEnabled = false
        store.signingReminderEnabled = false
        store.importNotificationsEnabled = true
        store.reset()

        XCTAssertEqual(store.defaultRate, 1.0, accuracy: 0.001)
        XCTAssertEqual(store.skipForwardSeconds, 15)
        XCTAssertTrue(store.resumeEnabled)
        XCTAssertTrue(store.autoPlayNext)
        XCTAssertTrue(store.signingReminderEnabled)
        XCTAssertFalse(store.importNotificationsEnabled)

        store.defaultRate = 2.5
        AppSettingsStore.clearStoredValues(defaults: defaults, keyPrefix: prefix)
        let restored = AppSettingsStore(defaults: defaults, keyPrefix: prefix)
        XCTAssertEqual(restored.defaultRate, 1.0, accuracy: 0.001)
    }

    func testLibraryScopeDefaultsPersistsAndRejectsUnknownValues() {
        let store = AppSettingsStore(defaults: defaults, keyPrefix: prefix)
        XCTAssertEqual(store.libraryScope, .items)

        store.libraryScope = .collections
        let restored = AppSettingsStore(defaults: defaults, keyPrefix: prefix)
        XCTAssertEqual(restored.libraryScope, .collections)

        // Garbage never traps the library in an unknown pane.
        defaults.set("weekly", forKey: prefix + AppSettingsStore.keyLibraryScope)
        let invalid = AppSettingsStore(defaults: defaults, keyPrefix: prefix)
        XCTAssertEqual(invalid.libraryScope, .items)
    }

    func testResetRestoresItemsScope() {
        let store = AppSettingsStore(defaults: defaults, keyPrefix: prefix)
        store.libraryScope = .collections
        store.reset()

        XCTAssertEqual(store.libraryScope, .items)
        let restored = AppSettingsStore(defaults: defaults, keyPrefix: prefix)
        XCTAssertEqual(restored.libraryScope, .items)
    }
}
