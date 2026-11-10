import XCTest
@testable import LocalPodKit

final class PlaybackPolicyTests: XCTestCase {
    func testRequiredSpeedPresetsAreAvailable() {
        let presets = PlaybackPolicy.speedPresets
        for required: Float in [0.5, 1.0, 1.5, 2.0, 3.0] {
            XCTAssertTrue(presets.contains(required), "missing \(required)x preset")
        }
        XCTAssertEqual(presets, presets.sorted())
    }

    func testRateIsClampedToSupportedRange() {
        XCTAssertEqual(PlaybackPolicy.clampedRate(0.1), 0.5)
        XCTAssertEqual(PlaybackPolicy.clampedRate(0.5), 0.5)
        XCTAssertEqual(PlaybackPolicy.clampedRate(1.25), 1.25)
        XCTAssertEqual(PlaybackPolicy.clampedRate(3.0), 3.0)
        XCTAssertEqual(PlaybackPolicy.clampedRate(9.0), 3.0)
        XCTAssertEqual(PlaybackPolicy.clampedRate(.nan), 1.0)
    }

    func testSpeedLabel() {
        XCTAssertEqual(PlaybackPolicy.speedLabel(0.5), "0.5×")
        XCTAssertEqual(PlaybackPolicy.speedLabel(1), "1.0×")
        XCTAssertEqual(PlaybackPolicy.speedLabel(1.25), "1.2×")
        XCTAssertEqual(PlaybackPolicy.speedLabel(3), "3.0×")
    }

    func testCompletionUsesNinetyFivePercentForShortAndLongMedia() {
        XCTAssertFalse(PlaybackPolicy.isFinished(position: 10, duration: 20))
        XCTAssertTrue(PlaybackPolicy.isFinished(position: 19, duration: 20))
        XCTAssertFalse(PlaybackPolicy.isFinished(position: 100, duration: 300))
        // A 300s item is finished at 270s even though that is only 90%,
        // because the remaining 30s rule applies to podcast-length audio.
        XCTAssertTrue(PlaybackPolicy.isFinished(position: 271, duration: 300))
        XCTAssertTrue(PlaybackPolicy.isFinished(position: 285, duration: 300))
    }

    func testShortClipsDoNotCountTheLastThirtySecondsRule() {
        // A 20s clip at 0s has "30s remaining"; it must not be finished.
        XCTAssertFalse(PlaybackPolicy.isFinished(position: 0, duration: 20))
        XCTAssertFalse(PlaybackPolicy.isFinished(position: 5, duration: 40))
        XCTAssertTrue(PlaybackPolicy.isFinished(position: 60, duration: 61))
    }

    func testCompletionHandlesInvalidInput() {
        XCTAssertFalse(PlaybackPolicy.isFinished(position: 1, duration: 0))
        XCTAssertFalse(PlaybackPolicy.isFinished(position: .nan, duration: 100))
        XCTAssertFalse(PlaybackPolicy.isFinished(position: 10, duration: .infinity))
    }

    func testResumeWindow() {
        XCTAssertFalse(PlaybackPolicy.shouldResume(position: 0, duration: 300, isFinished: false))
        XCTAssertFalse(PlaybackPolicy.shouldResume(position: 3, duration: 300, isFinished: false))
        XCTAssertTrue(PlaybackPolicy.shouldResume(position: 3.5, duration: 300, isFinished: false))
        XCTAssertTrue(PlaybackPolicy.shouldResume(position: 150, duration: 300, isFinished: false))
        XCTAssertFalse(PlaybackPolicy.shouldResume(position: 270, duration: 300, isFinished: false))
        XCTAssertFalse(PlaybackPolicy.shouldResume(position: 100, duration: 300, isFinished: true))
        XCTAssertFalse(PlaybackPolicy.shouldResume(position: 100, duration: 0, isFinished: false))
        XCTAssertFalse(PlaybackPolicy.shouldResume(position: 40, duration: 60, isFinished: false))
    }

    func testResumePosition() {
        XCTAssertEqual(
            PlaybackPolicy.resumePosition(position: 120, duration: 300, isFinished: false),
            120
        )
        XCTAssertEqual(
            PlaybackPolicy.resumePosition(position: 120, duration: 300, isFinished: true),
            0
        )
        XCTAssertEqual(
            PlaybackPolicy.resumePosition(position: 299, duration: 300, isFinished: false),
            0
        )
    }

    func testInterruptionResumeDecision() {
        XCTAssertTrue(PlaybackPolicy.shouldResumeAfterInterruption(
            wasPlaying: true,
            optionsContainShouldResume: true
        ))
        XCTAssertFalse(PlaybackPolicy.shouldResumeAfterInterruption(
            wasPlaying: true,
            optionsContainShouldResume: false
        ))
        XCTAssertFalse(PlaybackPolicy.shouldResumeAfterInterruption(
            wasPlaying: false,
            optionsContainShouldResume: true
        ))
    }
}
