import XCTest
@testable import LocalPodKit

@MainActor
final class SleepTimerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testOneMinuteFadesThenFiresAtDeadline() {
        let timer = SleepTimer(now: { self.start })
        var volumes: [Float] = []
        var fireCount = 0
        timer.onVolumeChange = { volumes.append($0) }
        timer.onFire = { fireCount += 1 }

        timer.start(minutes: 1)
        XCTAssertEqual(timer.mode, .minutes(1))
        XCTAssertEqual(timer.remainingSeconds, 60)

        timer.tick(now: start.addingTimeInterval(45))
        XCTAssertEqual(timer.remainingSeconds ?? -1, 15, accuracy: 0.01)
        XCTAssertFalse(timer.isFading)

        timer.tick(now: start.addingTimeInterval(50))
        XCTAssertTrue(timer.isFading)
        XCTAssertEqual(timer.remainingSeconds ?? -1, 10, accuracy: 0.01)
        XCTAssertEqual(volumes.last ?? -1, 1.0, accuracy: 0.01)

        timer.tick(now: start.addingTimeInterval(55))
        XCTAssertEqual(volumes.last ?? -1, 0.5, accuracy: 0.02)

        timer.tick(now: start.addingTimeInterval(60))
        XCTAssertEqual(fireCount, 1)
        XCTAssertEqual(timer.mode, .off)
        XCTAssertFalse(timer.isFading)
        XCTAssertEqual(volumes.last ?? -1, 0.0, accuracy: 0.01)

        timer.tick(now: start.addingTimeInterval(61))
        XCTAssertEqual(fireCount, 1, "a fired timer must not fire twice")
    }

    func testCancelDuringFadeRestoresVolumeAndDoesNotFire() {
        let timer = SleepTimer(now: { self.start })
        var volumes: [Float] = []
        var fireCount = 0
        timer.onVolumeChange = { volumes.append($0) }
        timer.onFire = { fireCount += 1 }

        timer.start(minutes: 1)
        timer.tick(now: start.addingTimeInterval(55))
        XCTAssertTrue(timer.isFading)

        timer.cancel()
        XCTAssertEqual(timer.mode, .off)
        XCTAssertFalse(timer.isFading)
        XCTAssertNil(timer.remainingSeconds)
        XCTAssertEqual(volumes.last ?? -1, 1.0, accuracy: 0.001)
        XCTAssertEqual(fireCount, 0)
    }

    func testEndOfEpisodeConsumesExactlyOnce() {
        let timer = SleepTimer(now: { self.start })
        timer.startEndOfEpisode()
        XCTAssertEqual(timer.mode, .endOfEpisode)
        XCTAssertNil(timer.remainingSeconds)

        XCTAssertTrue(timer.consumeEndOfEpisode())
        XCTAssertEqual(timer.mode, .off)
        XCTAssertFalse(timer.consumeEndOfEpisode())
    }

    func testRemainingTextFormatsMinutesAndSeconds() {
        let timer = SleepTimer(now: { self.start })
        timer.start(minutes: 2)
        timer.tick(now: start.addingTimeInterval(61))
        XCTAssertEqual(timer.mode, .minutes(2))
        XCTAssertEqual(timer.remainingSeconds ?? -1, 59, accuracy: 0.01)
        XCTAssertEqual(timer.remainingText, "0:59")
    }
}
