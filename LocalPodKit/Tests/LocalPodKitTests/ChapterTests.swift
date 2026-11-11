import AVFoundation
import XCTest
@testable import LocalPodKit

@MainActor
final class ChapterTests: XCTestCase {
    private var controller: PlaybackController!

    override func setUpWithError() throws {
        controller = PlaybackController()
    }

    override func tearDownWithError() throws {
        controller?.pause()
        controller = nil
    }

    private var chapteredAudioURL: URL {
        guard let url = Bundle.module.url(
            forResource: "demo-chaptered-audio",
            withExtension: "m4a"
        ) else {
            fatalError("Missing demo-chaptered-audio.m4a test fixture")
        }
        return url
    }

    private var plainAudioURL: URL {
        guard let url = Bundle.module.url(
            forResource: "demo-audio",
            withExtension: "m4a"
        ) else {
            fatalError("Missing demo-audio.m4a test fixture")
        }
        return url
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

    private func loadChapteredFixture(autoplay: Bool = false) async throws {
        controller.load(PlaybackItem(
            title: "章节音频",
            subtitle: "P2 测试",
            fileURL: chapteredAudioURL,
            kind: .audio
        ), autoplay: autoplay)
        try await waitUntil(message: "chapters never loaded") {
            self.controller.chapters.count == 3
        }
    }

    func testChapteredFixtureLoadsThreeChapters() async throws {
        try await loadChapteredFixture()
        let chapters = controller.chapters
        XCTAssertEqual(chapters.map(\.title), [
            "Chapter One", "Chapter Two", "Chapter Three"
        ])
        XCTAssertEqual(chapters[0].start, 0, accuracy: 0.5)
        XCTAssertEqual(chapters[1].start, 60, accuracy: 0.5)
        XCTAssertEqual(chapters[2].start, 120, accuracy: 0.5)
        for chapter in chapters {
            XCTAssertEqual(chapter.duration, 60, accuracy: 1)
        }
    }

    func testChaptersClearOnNewLoadAndItemSwitch() async throws {
        try await loadChapteredFixture()

        // A chapterless item resets the list immediately, and a stale async
        // chapter load must not republish the old file's chapters.
        controller.load(PlaybackItem(
            title: "无章节",
            subtitle: "P2 测试",
            fileURL: plainAudioURL,
            kind: .audio
        ), autoplay: false)
        XCTAssertTrue(controller.chapters.isEmpty)
        try await waitUntil(message: "chapterless item never became ready") {
            self.controller.phase == .ready
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(
            controller.chapters.isEmpty,
            "stale chapter load must not leak into the next item"
        )
    }

    func testChapterlessFileYieldsNoChapters() async throws {
        controller.load(PlaybackItem(
            title: "无章节",
            subtitle: "P2 测试",
            fileURL: plainAudioURL,
            kind: .audio
        ), autoplay: false)
        try await waitUntil(message: "chapterless item never became ready") {
            self.controller.phase == .ready
        }
        // Give the async chapter read the same head start the UI would have.
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(controller.chapters.isEmpty)
        XCTAssertNil(controller.currentChapterIndex)
    }

    func testCurrentChapterIndexTracksSeekPosition() async throws {
        try await loadChapteredFixture()

        controller.seek(to: 0)
        try await waitUntil(message: "seek to 0 never settled") {
            abs(self.controller.currentTime - 0) < 1
        }
        XCTAssertEqual(controller.currentChapterIndex, 0)

        controller.seek(to: 61)
        try await waitUntil(message: "seek to 61 never settled") {
            abs(self.controller.currentTime - 61) < 1
        }
        XCTAssertEqual(controller.currentChapterIndex, 1)

        controller.seek(to: 150)
        try await waitUntil(message: "seek to 150 never settled") {
            abs(self.controller.currentTime - 150) < 1
        }
        XCTAssertEqual(controller.currentChapterIndex, 2)
    }

    func testCurrentChapterIndexNilBeforeChaptersLoad() async throws {
        controller.load(PlaybackItem(
            title: "章节音频",
            subtitle: "P2 测试",
            fileURL: chapteredAudioURL,
            kind: .audio
        ), autoplay: false)
        // Chapters arrive asynchronously; before that the index is nil even
        // though the item is already current.
        XCTAssertNil(controller.currentChapterIndex)
        try await waitUntil { self.controller.chapters.count == 3 }
        XCTAssertEqual(controller.currentChapterIndex, 0)
    }

    func testChapterIndexBoundaries() {
        let chapters = [
            ChapterInfo(title: "A", start: 0, duration: 60),
            ChapterInfo(title: "B", start: 60, duration: 60),
            ChapterInfo(title: "C", start: 120, duration: 0)
        ]

        XCTAssertNil(ChapterInfo.index(at: -1, in: chapters))
        XCTAssertNil(ChapterInfo.index(at: .nan, in: chapters))
        XCTAssertNil(ChapterInfo.index(at: 10, in: []))
        XCTAssertEqual(ChapterInfo.index(at: 0, in: chapters), 0)
        XCTAssertEqual(ChapterInfo.index(at: 59.9, in: chapters), 0)
        // A gap between chapters has no owner.
        XCTAssertNil(ChapterInfo.index(at: 60.5, in: [
            ChapterInfo(title: "A", start: 0, duration: 60),
            ChapterInfo(title: "B", start: 70, duration: 60)
        ]))
        XCTAssertEqual(ChapterInfo.index(at: 70, in: chapters), 1)
        XCTAssertEqual(ChapterInfo.index(at: 120, in: chapters), 2)
        // Zero-duration last chapter owns everything to the end of the file.
        XCTAssertEqual(ChapterInfo.index(at: 10_000, in: chapters), 2)
        // Time past a known bounded chapter end (no next chapter covers it)
        // and past every chapter start with a bounded final chapter.
        XCTAssertNil(ChapterInfo.index(at: 10_000, in: [
            ChapterInfo(title: "A", start: 0, duration: 60)
        ]))
    }

    func testChapterInfoCodableRoundTripAndEquality() throws {
        let chapter = ChapterInfo(title: "第 1 章", start: 1.5, duration: 30.25)
        let data = try JSONEncoder().encode([chapter])
        let decoded = try JSONDecoder().decode([ChapterInfo].self, from: data)
        XCTAssertEqual(decoded, [chapter])

        let copy = ChapterInfo(title: "第 1 章", start: 1.5, duration: 30.25)
        XCTAssertEqual(chapter, copy)
        XCTAssertEqual(chapter.id, copy.id, "identical chapters must share an id")
        XCTAssertNotEqual(
            chapter.id,
            ChapterInfo(title: "第 2 章", start: 1.5, duration: 30.25).id
        )
    }

    func testPlaybackItemCarriesChapters() {
        let chapters = [ChapterInfo(title: "A", start: 0, duration: 10)]
        let item = PlaybackItem(
            title: "t",
            subtitle: "s",
            fileURL: chapteredAudioURL,
            kind: .audio,
            chapters: chapters
        )
        XCTAssertEqual(item.chapters, chapters)
        // The default keeps the existing call sites' behavior.
        XCTAssertTrue(
            PlaybackItem(
                title: "t",
                subtitle: "s",
                fileURL: chapteredAudioURL,
                kind: .audio
            ).chapters.isEmpty
        )
    }
}
