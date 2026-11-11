import Foundation
import SwiftData
import XCTest
@testable import LocalPodKit

@MainActor
final class PlaybackSessionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var store: PlaybackProgressStore!
    private var settings: AppSettingsStore!
    private var sleepTimer: SleepTimer!
    private var session: PlaybackSession!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private let idA = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
    private let idB = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
    private let idC = UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!

    override func setUp() async throws {
        container = try LocalPodStore.makeContainer(inMemory: true)
        context = container.mainContext
        store = PlaybackProgressStore(context: context)

        for (id, title) in [(idA, "A"), (idB, "B"), (idC, "C")] {
            context.insert(MediaItem(
                id: id,
                title: title,
                relativePath: "Media/\(id.uuidString).m4a",
                kind: .audio,
                fileExtension: "m4a",
                byteSize: 100,
                durationSeconds: 20
            ))
        }
        try context.save()

        suiteName = "LocalPodSessionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        settings = AppSettingsStore(
            defaults: defaults,
            keyPrefix: "localpod.session.test."
        )
        sleepTimer = SleepTimer(now: { [fixedNow] in fixedNow })
        session = makeSession()
        session.attach(context: context, progressStore: store)
    }

    override func tearDown() async throws {
        session?.playback.stop()
        session = nil
        sleepTimer = nil
        settings = nil
        store = nil
        context = nil
        container = nil
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
    }

    private func makeSession() -> PlaybackSession {
        PlaybackSession(
            settings: settings,
            sleepTimer: sleepTimer,
            itemBuilder: { item in
                PlaybackItem(
                    title: item.title,
                    subtitle: "测试",
                    fileURL: TestFixtures.audioURL,
                    kind: .audio,
                    durationHint: 20,
                    libraryItemID: item.id
                )
            }
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 10,
        message: String = "condition not met",
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("\(message) (timeout \(timeout)s)")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func mediaItem(_ id: UUID) -> MediaItem {
        var descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try! context.fetch(descriptor).first!
    }

    func testPlayAllAndAutoAdvance() async throws {
        session.play(items: [mediaItem(idA), mediaItem(idB)])
        try await waitUntil {
            self.session.playback.currentItem?.title == "A"
                && self.session.playback.isPlaying
        }
        XCTAssertEqual(session.queue.itemIDs, [idA, idB])
        XCTAssertEqual(session.queue.currentItemID, idA)

        session.handleItemEnded()
        try await waitUntil(message: "queue did not advance to B") {
            self.session.queue.currentItemID == self.idB
                && self.session.playback.currentItem?.title == "B"
                && self.session.playback.isPlaying
        }
    }

    func testAutoPlayNextCanBeDisabled() async throws {
        settings.autoPlayNext = false
        session.play(items: [mediaItem(idA), mediaItem(idB)])
        try await waitUntil { self.session.playback.isPlaying }

        session.handleItemEnded()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(session.queue.currentItemID, idA)
        XCTAssertEqual(session.playback.currentItem?.title, "A")
    }

    func testEndOfEpisodeSleepModeSuppressesAutoAdvance() async throws {
        session.play(items: [mediaItem(idA), mediaItem(idB)])
        try await waitUntil { self.session.playback.isPlaying }
        session.startSleepTimerEndOfEpisode()

        session.handleItemEnded()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(session.queue.currentItemID, idA)
        XCTAssertEqual(session.playback.currentItem?.title, "A")
        XCTAssertEqual(session.sleepTimer.mode, .off)
    }

    func testDeletingCurrentItemAdvancesThenStopsWhenEmpty() async throws {
        session.play(items: [mediaItem(idA), mediaItem(idB)])
        try await waitUntil { self.session.playback.isPlaying }

        session.handleDeletedItem(idA)
        try await waitUntil(message: "deleted current item did not advance") {
            self.session.queue.currentItemID == self.idB
                && self.session.playback.currentItem?.title == "B"
        }
        XCTAssertEqual(session.queue.itemIDs, [idB])

        session.handleDeletedItem(idB)
        try await waitUntil(message: "empty queue did not return to idle") {
            self.session.playback.phase == .idle
                && self.session.playback.currentItem == nil
        }
        XCTAssertTrue(session.queue.isEmpty)
    }

    func testPlayNextAndEnqueueSemantics() async throws {
        session.play(items: [mediaItem(idA)])
        try await waitUntil { self.session.playback.isPlaying }

        session.playNext(itemID: idB)
        session.enqueue(itemID: idC)
        XCTAssertEqual(session.queue.itemIDs, [idA, idB, idC])
        XCTAssertEqual(session.queue.currentItemID, idA)
    }

    func testQueueRestoresPausedAfterRelaunch() async throws {
        session.play(items: [mediaItem(idA), mediaItem(idB)], startingAt: 1)
        try await waitUntil {
            self.session.playback.currentItem?.title == "B"
                && self.session.playback.isPlaying
        }
        session.playback.pause()

        let restored = makeSession()
        restored.attach(context: context, progressStore: store)
        try await waitUntil(message: "restored queue item did not load") {
            restored.playback.currentItem?.title == "B"
                && restored.playback.phase == .ready
        }
        XCTAssertEqual(restored.queue.itemIDs, [idA, idB])
        XCTAssertEqual(restored.queue.currentItemID, idB)
        XCTAssertFalse(restored.playback.isPlaying, "restart must not auto-play")
        restored.playback.stop()
    }

    func testRestoreSkipsMissingCurrentItem() async throws {
        let missing = UUID()
        session.queue.setQueue(itemIDs: [idA, missing], current: missing)

        let restored = makeSession()
        restored.attach(context: context, progressStore: store)
        try await waitUntil(message: "missing item was not skipped") {
            restored.queue.currentItemID == self.idA
                && restored.playback.currentItem?.title == "A"
        }
        XCTAssertEqual(restored.queue.itemIDs, [idA])
        restored.playback.stop()
    }

    func testSleepTimerFirePausesPlaybackAndRestoresVolume() async throws {
        session.play(items: [mediaItem(idA)])
        try await waitUntil { self.session.playback.isPlaying }

        session.startSleepTimer(minutes: 1)
        sleepTimer.tick(now: fixedNow.addingTimeInterval(61))
        try await waitUntil(message: "sleep timer did not pause playback") {
            self.session.playback.phase == .paused
        }
        XCTAssertEqual(session.playback.player.volume, 1.0, accuracy: 0.001)
        XCTAssertEqual(session.sleepTimer.mode, .off)
    }

    // MARK: - Shortcuts resume

    func testResumeForShortcutStartsQueuedCurrentItem() async throws {
        session.queue.setQueue(itemIDs: [idA, idB], current: idB)

        XCTAssertTrue(session.resumeForShortcut())
        XCTAssertEqual(session.queue.currentItemID, idB)
        try await waitUntil(message: "shortcut did not start the queued item") {
            self.session.playback.currentItem?.title == "B"
                && self.session.playback.isPlaying
        }
    }

    func testResumeForShortcutFallsBackToMostRecentUnfinishedProgress() async throws {
        // A is older, B is the most recent unfinished item, and C is finished
        // (and newer) so it must be ignored.
        context.insert(PlaybackState(
            itemID: idA,
            position: 5,
            duration: 20,
            isFinished: false,
            playCount: 1,
            lastPlayedAt: fixedNow.addingTimeInterval(-600)
        ))
        context.insert(PlaybackState(
            itemID: idB,
            position: 7,
            duration: 20,
            isFinished: false,
            playCount: 2,
            lastPlayedAt: fixedNow
        ))
        context.insert(PlaybackState(
            itemID: idC,
            position: 20,
            duration: 20,
            isFinished: true,
            playCount: 3,
            lastPlayedAt: fixedNow.addingTimeInterval(60)
        ))
        try context.save()

        XCTAssertTrue(session.resumeForShortcut())
        XCTAssertEqual(session.queue.itemIDs, [idB])
        XCTAssertEqual(session.queue.currentItemID, idB)
        try await waitUntil(message: "shortcut did not resume the recent unfinished item") {
            self.session.playback.currentItem?.title == "B"
                && self.session.playback.isPlaying
        }
    }

    func testResumeForShortcutReturnsFalseWhenNothingPlayable() {
        XCTAssertTrue(session.queue.isEmpty)
        XCTAssertFalse(session.resumeForShortcut())
        XCTAssertNil(session.playback.currentItem)
    }

    func testRepeatOneReloadsCurrentItemOnEnd() async throws {
        session.play(items: [mediaItem(idA), mediaItem(idB)])
        try await waitUntil { self.session.playback.isPlaying }
        session.queue.setRepeatMode(.one)

        session.handleItemEnded()
        try await waitUntil(message: "repeat one did not restart the item") {
            self.session.playback.currentItem?.title == "A"
                && self.session.playback.isPlaying
        }
        XCTAssertEqual(session.queue.currentItemID, idA)
    }
}
