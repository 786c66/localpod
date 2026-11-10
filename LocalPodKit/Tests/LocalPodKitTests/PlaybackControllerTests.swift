import AVFoundation
import MediaPlayer
import SwiftData
import XCTest
@testable import LocalPodKit

@MainActor
final class PlaybackControllerTests: XCTestCase {
    private var container: ModelContainer!
    private var store: PlaybackProgressStore!
    private var controller: PlaybackController!

    override func setUpWithError() throws {
        container = try LocalPodStore.makeContainer(inMemory: true)
        store = PlaybackProgressStore(context: container.mainContext)
        controller = PlaybackController()
        controller.attachProgressStore(store)
    }

    override func tearDownWithError() throws {
        controller?.pause()
        controller = nil
        store = nil
        container = nil
    }

    private var longAudioURL: URL {
        guard let url = Bundle.module.url(
            forResource: "demo-long-audio",
            withExtension: "m4a"
        ) else {
            fatalError("Missing demo-long-audio.m4a test fixture")
        }
        return url
    }

    private func makeLongItem(libraryItemID: UUID? = nil) -> PlaybackItem {
        PlaybackItem(
            title: "长音频",
            subtitle: "M2 测试",
            fileURL: longAudioURL,
            kind: .audio,
            libraryItemID: libraryItemID
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

    func testLongAudioLoadsAndReportsDuration() async throws {
        controller.load(makeLongItem(), autoplay: false)
        try await waitUntil(message: "item never became ready") {
            self.controller.phase == .ready
                && self.controller.duration > 60
        }
        XCTAssertEqual(controller.currentItem?.title, "长音频")
        XCTAssertEqual(controller.duration, 298.19, accuracy: 3)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertNotNil(controller.player.currentItem)
        XCTAssertEqual(controller.player.currentItem?.audioTimePitchAlgorithm, .timeDomain)
        XCTAssertNil(controller.errorMessage)
    }

    func testPlayPauseAndSeekUpdateTime() async throws {
        controller.load(makeLongItem(), autoplay: false)
        try await waitUntil { self.controller.phase == .ready && self.controller.duration > 60 }

        controller.seek(to: 120)
        try await waitUntil(message: "seek did not settle") {
            abs(self.controller.currentTime - 120) < 2
        }

        controller.skip(by: 15)
        try await waitUntil { abs(self.controller.currentTime - 135) < 2 }
        controller.skip(by: -30)
        try await waitUntil { abs(self.controller.currentTime - 105) < 2 }

        controller.play()
        XCTAssertEqual(controller.phase, .playing)
        try await waitUntil { self.controller.player.rate > 0 }
        let startTime = controller.currentTime
        try await waitUntil(timeout: 5, message: "playback time did not advance") {
            self.controller.currentTime > startTime + 0.1
        }

        controller.pause()
        XCTAssertEqual(controller.phase, .paused)
        XCTAssertEqual(controller.player.rate, 0)
    }

    func testRatePresetsAndPitchCorrection() async throws {
        controller.load(makeLongItem(), autoplay: false)
        try await waitUntil { self.controller.phase == .ready }

        for rate: Float in [0.5, 1.0, 1.5, 2.0, 3.0] {
            controller.setRate(rate)
            XCTAssertEqual(controller.playbackRate, rate)
        }
        controller.setRate(10)
        XCTAssertEqual(controller.playbackRate, 3.0)
        controller.setRate(0.1)
        XCTAssertEqual(controller.playbackRate, 0.5)
        controller.setRate(1.5)
        XCTAssertEqual(
            controller.player.currentItem?.audioTimePitchAlgorithm,
            .timeDomain
        )

        controller.play()
        try await waitUntil { abs(self.controller.player.rate - 1.5) < 0.01 }
        XCTAssertEqual(controller.phase, .playing)
    }

    func testProgressPersistsWhilePlayingAndResumesWithinTwoSeconds() async throws {
        let libraryID = UUID()
        let item = makeLongItem(libraryItemID: libraryID)

        controller.load(item, autoplay: true)
        try await waitUntil { self.controller.isPlaying && self.controller.duration > 60 }
        controller.seek(to: 90)
        try await Task.sleep(nanoseconds: 1_300_000_000)
        controller.pause()

        let saved = try XCTUnwrap(try store.state(for: libraryID))
        XCTAssertGreaterThan(saved.position, 89)
        XCTAssertEqual(saved.playCount, 1)
        XCTAssertFalse(saved.isFinished)
        XCTAssertNotNil(saved.lastPlayedAt)

        let second = PlaybackController()
        second.attachProgressStore(store)
        second.load(item, autoplay: false)
        try await waitUntil {
            second.phase == .ready && second.duration > 60
        }
        XCTAssertEqual(second.currentTime, saved.position, accuracy: 2)
        XCTAssertEqual(second.phase, .ready)
        second.pause()
    }

    func testFinishedItemDoesNotAutoResumeAndReplayStartsAtZero() async throws {
        let libraryID = UUID()
        let item = makeLongItem(libraryItemID: libraryID)

        controller.load(item, autoplay: false)
        try await waitUntil { self.controller.phase == .ready && self.controller.duration > 60 }
        controller.seek(to: controller.duration - 0.5)
        controller.play()
        try await waitUntil(timeout: 15, message: "item never ended") {
            self.controller.phase == .ended
        }

        let finished = try XCTUnwrap(try store.state(for: libraryID))
        XCTAssertTrue(finished.isFinished)
        XCTAssertEqual(finished.position, finished.duration, accuracy: 1)

        let second = PlaybackController()
        second.attachProgressStore(store)
        second.load(item, autoplay: false)
        try await waitUntil { second.phase == .ready }
        XCTAssertEqual(second.currentTime, 0)
        XCTAssertFalse(second.isPlaying)
        XCTAssertTrue(
            try XCTUnwrap(store.state(for: libraryID)).isFinished,
            "loading a finished item must not clear the finished flag"
        )

        second.play()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(try XCTUnwrap(store.state(for: libraryID)).isFinished)
        second.pause()
    }

    func testAudioKeepsPlayingInBackgroundButVideoPausesAndResumes() async throws {
        controller.load(makeLongItem(), autoplay: true)
        try await waitUntil { self.controller.isPlaying }
        controller.handleSceneDidEnterBackground()
        XCTAssertTrue(controller.isPlaying)
        XCTAssertTrue(controller.phase == .playing || controller.phase == .buffering)

        let videoURL = TestFixtures.videoURL
        let video = PlaybackItem(
            title: "视频",
            subtitle: "M2 测试",
            fileURL: videoURL,
            kind: .video
        )
        controller.load(video, autoplay: true)
        try await waitUntil { self.controller.isPlaying }
        controller.handleSceneDidEnterBackground()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.phase, .paused)

        controller.handleSceneWillEnterForeground()
        XCTAssertTrue(controller.isPlaying)
        XCTAssertEqual(controller.phase, .playing)
    }

    func testPictureInPictureVideoKeepsPlayingWhenBackgrounded() async throws {
        let videoURL = TestFixtures.videoURL
        controller.load(PlaybackItem(
            title: "视频",
            subtitle: "PiP",
            fileURL: videoURL,
            kind: .video
        ), autoplay: true)
        try await waitUntil { self.controller.isPlaying }

        controller.setPictureInPictureActive(true)
        controller.handleSceneDidEnterBackground()
        XCTAssertTrue(controller.isPlaying)
        XCTAssertTrue(controller.phase == .playing || controller.phase == .buffering)
    }

    func testNowPlayingMetadataAndRemoteCommands() async throws {
        controller.load(makeLongItem(), autoplay: true)
        try await waitUntil { self.controller.isPlaying }

        let info = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "长音频")
        XCTAssertEqual(info[MPMediaItemPropertyArtist] as? String, "M2 测试")
        XCTAssertEqual(info[MPMediaItemPropertyAlbumTitle] as? String, "M2 测试")
        let nowPlayingDuration = try XCTUnwrap(
            info[MPMediaItemPropertyPlaybackDuration] as? Double
        )
        XCTAssertGreaterThan(nowPlayingDuration, 60)
        let rate = try XCTUnwrap(
            info[MPNowPlayingInfoPropertyPlaybackRate] as? Double
        )
        XCTAssertGreaterThan(rate, 0)

        controller.pause()
        let pausedInfo = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(
            pausedInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0,
            0
        )

        let center = MPRemoteCommandCenter.shared()
        XCTAssertTrue(center.playCommand.isEnabled)
        XCTAssertTrue(center.pauseCommand.isEnabled)
        XCTAssertTrue(center.togglePlayPauseCommand.isEnabled)
        XCTAssertTrue(center.skipForwardCommand.isEnabled)
        XCTAssertTrue(center.skipBackwardCommand.isEnabled)
        XCTAssertEqual(center.skipForwardCommand.preferredIntervals, [15])
        XCTAssertEqual(center.skipBackwardCommand.preferredIntervals, [15])
        XCTAssertTrue(center.changePlaybackPositionCommand.isEnabled)
    }

    func testOneHundredItemSwitchesDoNotCrash() async throws {
        for index in 0..<100 {
            let item = PlaybackItem(
                title: "切换 \(index)",
                subtitle: "M2",
                fileURL: longAudioURL,
                kind: .audio
            )
            controller.load(item, autoplay: index.isMultiple(of: 2))
            if index.isMultiple(of: 10) {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        try await waitUntil(timeout: 10, message: "final item did not load") {
            self.controller.currentItem?.title == "切换 99"
        }
        controller.pause()
        XCTAssertEqual(controller.currentItem?.title, "切换 99")
        XCTAssertNil(controller.errorMessage)
    }
}
