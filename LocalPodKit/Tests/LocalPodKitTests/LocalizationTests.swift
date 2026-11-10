import Foundation
import XCTest
@testable import LocalPodKit

/// Verification that display names resolve against an explicit locale instead
/// of the host Mac's language.
final class LocalizationTests: XCTestCase {
    private let zh = Locale(identifier: "zh-Hans")
    private let en = Locale(identifier: "en")

    func testSourceDisplayNames() {
        XCTAssertEqual(MediaSource.imported.displayName(locale: zh), "导入")
        XCTAssertEqual(MediaSource.imported.displayName(locale: en), "Imported")
        XCTAssertEqual(MediaSource.openIn.displayName(locale: zh), "外部打开")
        XCTAssertEqual(MediaSource.openIn.displayName(locale: en), "Open In")
        XCTAssertEqual(MediaSource.sample.displayName(locale: zh), "示例")
        XCTAssertEqual(MediaSource.sample.displayName(locale: en), "Sample")
        for source in MediaSource.allCases {
            XCTAssertFalse(source.displayName(locale: en).isEmpty)
        }
    }

    func testKindDisplayNames() {
        XCTAssertEqual(MediaKind.audio.displayName(locale: zh), "音频")
        XCTAssertEqual(MediaKind.audio.displayName(locale: en), "Audio")
        XCTAssertEqual(MediaKind.video.displayName(locale: zh), "视频")
        XCTAssertEqual(MediaKind.video.displayName(locale: en), "Video")
    }

    func testImportPhaseDisplayNames() {
        XCTAssertEqual(ImportPhase.scanning.displayName(locale: zh), "扫描中")
        XCTAssertEqual(ImportPhase.scanning.displayName(locale: en), "Scanning")
        XCTAssertEqual(ImportPhase.downloading.displayName(locale: en), "Downloading from iCloud")
        XCTAssertEqual(ImportPhase.finished.displayName(locale: en), "Finished")
    }

    func testImportIssueKindDisplayNames() {
        XCTAssertEqual(ImportIssueKind.duplicate.displayName(locale: zh), "重复")
        XCTAssertEqual(ImportIssueKind.duplicate.displayName(locale: en), "Duplicate")
        XCTAssertEqual(ImportIssueKind.cloudDownloadFailed.displayName(locale: en), "iCloud Download Failed")
        XCTAssertEqual(ImportIssueKind.other.displayName(locale: en), "Other")
    }

    func testRepeatModeAndPlaybackPhaseDisplayNames() {
        XCTAssertEqual(QueueRepeatMode.off.displayName(locale: zh), "不循环")
        XCTAssertEqual(QueueRepeatMode.off.displayName(locale: en), "Repeat Off")
        XCTAssertEqual(QueueRepeatMode.one.displayName(locale: en), "Repeat One")
        XCTAssertEqual(PlaybackPhase.playing.statusText(locale: zh), "播放中")
        XCTAssertEqual(PlaybackPhase.playing.statusText(locale: en), "Playing")
        XCTAssertEqual(PlaybackPhase.ended.statusText(locale: en), "Playback Ended")
    }

    func testSleepTimerModeDisplayNames() {
        XCTAssertEqual(SleepTimer.Mode.minutes(5).displayName(locale: zh), "5 分钟")
        XCTAssertEqual(SleepTimer.Mode.minutes(5).displayName(locale: en), "5 min")
        XCTAssertEqual(SleepTimer.Mode.endOfEpisode.displayName(locale: en), "End of Episode")
    }

    func testPackageErrorMessagesResolveEnglishAndChinese() {
        let url = URL(fileURLWithPath: "/tmp/example.m4a")
        XCTAssertEqual(
            MediaProbeError.notPlayable(url).localizedDescription,
            MediaProbeError.notPlayable(url).errorDescription
        )
        XCTAssertTrue(
            LocalPodLocalization.format(
                "error.probe.notPlayable",
                locale: zh,
                url.lastPathComponent
            ).contains("无法播放")
        )
        XCTAssertEqual(
            LocalPodLocalization.format(
                "error.import.duplicate",
                locale: en,
                "abcdef123456"
            ),
            "Duplicate content; skipped (first 12 SHA-256 characters: abcdef123456)."
        )
        XCTAssertEqual(
            LocalPodLocalization.string("source.sample", locale: en),
            "Sample"
        )
    }
}
