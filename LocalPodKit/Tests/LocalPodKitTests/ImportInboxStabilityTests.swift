import Foundation
import XCTest
@testable import LocalPodKit

final class ImportInboxStabilityTests: XCTestCase {
    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path
        )
    }

    private func makeInbox() throws -> (documents: TemporaryDirectory, inbox: ImportInbox) {
        let documents = try TemporaryDirectory()
        let inbox = try ImportInbox(documentsRoot: documents.url)
        try inbox.ensureExists()
        return (documents, inbox)
    }

    func testFirstObservationIsNeverStable() throws {
        let (documents, inbox) = try makeInbox()
        let file = try documents.write("Import/Episode.m4a", bytes: 16)
        let now = Date().addingTimeInterval(10)
        try setModificationDate(now.addingTimeInterval(-10), for: file)

        let tracker = ImportInboxStability()
        let result = try tracker.evaluate(in: inbox.directoryURL, now: now)

        XCTAssertTrue(result.stableURLs.isEmpty)
        XCTAssertEqual(result.unstableCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testSecondUnchangedObservationBecomesStable() throws {
        let (documents, inbox) = try makeInbox()
        let file = try documents.write("Import/Episode.m4a", bytes: 16)
        let now = Date().addingTimeInterval(10)
        try setModificationDate(now.addingTimeInterval(-10), for: file)

        let tracker = ImportInboxStability()
        _ = try tracker.evaluate(in: inbox.directoryURL, now: now)
        let result = try tracker.evaluate(in: inbox.directoryURL, now: now.addingTimeInterval(1.25))

        XCTAssertEqual(result.stableURLs.map(\.path), [file.standardizedFileURL.path])
        XCTAssertEqual(result.unstableCount, 0)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testObservationsMustBeAtLeastOneSecondApart() throws {
        let (documents, inbox) = try makeInbox()
        let file = try documents.write("Import/Episode.m4a", bytes: 16)
        let now = Date().addingTimeInterval(10)
        try setModificationDate(now.addingTimeInterval(-10), for: file)

        let tracker = ImportInboxStability()
        _ = try tracker.evaluate(in: inbox.directoryURL, now: now)

        let tooSoon = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(0.5)
        )
        XCTAssertTrue(tooSoon.stableURLs.isEmpty)
        XCTAssertEqual(tooSoon.unstableCount, 1)

        let later = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(1.75)
        )
        XCTAssertEqual(later.stableURLs.map(\.path), [file.standardizedFileURL.path])
    }

    func testNewestModificationDateMustBeAtLeastTwoSecondsOld() throws {
        let (documents, inbox) = try makeInbox()
        let file = try documents.write("Import/Episode.m4a", bytes: 16)
        let now = Date().addingTimeInterval(10)
        try setModificationDate(now.addingTimeInterval(-0.5), for: file)

        let tracker = ImportInboxStability()
        _ = try tracker.evaluate(in: inbox.directoryURL, now: now)

        let stillFresh = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(1.25)
        )
        XCTAssertTrue(stillFresh.stableURLs.isEmpty)
        XCTAssertEqual(stillFresh.unstableCount, 1)

        let quiet = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(2.5)
        )
        XCTAssertEqual(quiet.stableURLs.map(\.path), [file.standardizedFileURL.path])
    }

    func testChangedModificationDateResetsStability() throws {
        let (documents, inbox) = try makeInbox()
        let file = try documents.write("Import/Episode.m4a", bytes: 16)
        let now = Date().addingTimeInterval(10)
        try setModificationDate(now.addingTimeInterval(-10), for: file)

        let tracker = ImportInboxStability()
        _ = try tracker.evaluate(in: inbox.directoryURL, now: now)
        XCTAssertEqual(
            try tracker.evaluate(in: inbox.directoryURL, now: now.addingTimeInterval(1.25)).stableURLs.count,
            1
        )

        try setModificationDate(now.addingTimeInterval(-1), for: file)
        let changed = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(1.5)
        )
        XCTAssertTrue(changed.stableURLs.isEmpty)
        XCTAssertEqual(changed.unstableCount, 1)

        let settledAgain = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(2.75)
        )
        XCTAssertEqual(settledAgain.stableURLs.map(\.path), [file.standardizedFileURL.path])
    }

    func testChangedSizeResetsStability() throws {
        let (documents, inbox) = try makeInbox()
        let file = try documents.write("Import/Episode.m4a", bytes: 16)
        let now = Date().addingTimeInterval(10)
        let modificationDate = now.addingTimeInterval(-10)
        try setModificationDate(modificationDate, for: file)

        let tracker = ImportInboxStability()
        _ = try tracker.evaluate(in: inbox.directoryURL, now: now)
        XCTAssertEqual(
            try tracker.evaluate(in: inbox.directoryURL, now: now.addingTimeInterval(1.25)).stableURLs.count,
            1
        )

        // Same mtime, different size: only the size changed.
        try documents.write("Import/Episode.m4a", bytes: 32)
        try setModificationDate(modificationDate, for: file)

        let changed = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(2.5)
        )
        XCTAssertTrue(changed.stableURLs.isEmpty)
        XCTAssertEqual(changed.unstableCount, 1)

        let settledAgain = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(3.75)
        )
        XCTAssertEqual(settledAgain.stableURLs.map(\.path), [file.standardizedFileURL.path])
    }

    func testFolderTreeChangeResetsStability() throws {
        let (documents, inbox) = try makeInbox()
        let now = Date().addingTimeInterval(10)
        let folder = documents.url.appendingPathComponent("Import/Season", isDirectory: true)
        let firstFile = try documents.write("Import/Season/Disc 1/Episode 1.m4a", bytes: 16)
        try setModificationDate(now.addingTimeInterval(-10), for: firstFile)

        let tracker = ImportInboxStability()
        _ = try tracker.evaluate(in: inbox.directoryURL, now: now)
        XCTAssertEqual(
            try tracker.evaluate(in: inbox.directoryURL, now: now.addingTimeInterval(1.25)).stableURLs.count,
            1
        )

        let secondFile = try documents.write("Import/Season/Disc 1/Episode 2.m4a", bytes: 24)
        try setModificationDate(now.addingTimeInterval(-5), for: secondFile)

        let changed = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(2.5)
        )
        XCTAssertTrue(changed.stableURLs.isEmpty)
        XCTAssertEqual(changed.unstableCount, 1)

        let settledAgain = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(3.75)
        )
        XCTAssertEqual(settledAgain.stableURLs.map(\.path), [folder.standardizedFileURL.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondFile.path))
    }

    func testFolderWithChangingNestedFileNeverStabilizesEarly() throws {
        let (documents, inbox) = try makeInbox()
        let now = Date().addingTimeInterval(10)
        let folder = documents.url.appendingPathComponent("Import/Season", isDirectory: true)
        let nestedFile = try documents.write("Import/Season/Episode.m4a", bytes: 16)
        try setModificationDate(now.addingTimeInterval(-10), for: nestedFile)

        let tracker = ImportInboxStability()
        _ = try tracker.evaluate(in: inbox.directoryURL, now: now)

        try documents.write("Import/Season/Episode.m4a", bytes: 48)
        try setModificationDate(now.addingTimeInterval(-5), for: nestedFile)

        let changing = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(1.25)
        )
        XCTAssertTrue(changing.stableURLs.isEmpty)
        XCTAssertEqual(changing.unstableCount, 1)

        let settled = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(2.5)
        )
        XCTAssertEqual(settled.stableURLs.map(\.path), [folder.standardizedFileURL.path])
    }

    func testHiddenTopLevelItemsAreIgnored() throws {
        let (documents, inbox) = try makeInbox()
        let visible = try documents.write("Import/Episode.m4a", bytes: 16)
        let hidden = try documents.write("Import/.Episode.m4a", bytes: 16)
        let now = Date().addingTimeInterval(10)
        try setModificationDate(now.addingTimeInterval(-10), for: visible)
        try setModificationDate(now.addingTimeInterval(-10), for: hidden)

        XCTAssertEqual(try inbox.pendingURLs().map(\.lastPathComponent), ["Episode.m4a"])

        let tracker = ImportInboxStability()
        let first = try tracker.evaluate(in: inbox.directoryURL, now: now)
        XCTAssertTrue(first.stableURLs.isEmpty)
        XCTAssertEqual(first.unstableCount, 1)

        let second = try tracker.evaluate(in: inbox.directoryURL, now: now.addingTimeInterval(1.25))
        XCTAssertEqual(second.stableURLs.map(\.lastPathComponent), ["Episode.m4a"])
        XCTAssertEqual(second.unstableCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: hidden.path))
    }

    func testFrequentObservationsDoNotPostponeStability() throws {
        let (documents, inbox) = try makeInbox()
        let file = try documents.write("Import/Episode.m4a", bytes: 16)
        let now = Date().addingTimeInterval(10)
        try setModificationDate(now.addingTimeInterval(-10), for: file)

        let tracker = ImportInboxStability()
        _ = try tracker.evaluate(in: inbox.directoryURL, now: now)
        _ = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(0.5)
        )
        let result = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(1.25)
        )

        XCTAssertEqual(result.stableURLs.map(\.path), [file.standardizedFileURL.path])
        XCTAssertEqual(result.unstableCount, 0)
    }

    func testEmptyFolderPopulatedLaterResetsStability() throws {
        let (documents, inbox) = try makeInbox()
        let folder = documents.url.appendingPathComponent("Import/Season", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date().addingTimeInterval(10)

        let tracker = ImportInboxStability()
        _ = try tracker.evaluate(in: inbox.directoryURL, now: now)
        XCTAssertEqual(
            try tracker.evaluate(in: inbox.directoryURL, now: now.addingTimeInterval(1.25)).stableURLs.count,
            1
        )

        let nested = try documents.write("Import/Season/Disc 1/Episode 1.m4a", bytes: 16)
        try setModificationDate(now.addingTimeInterval(-5), for: nested)

        let changed = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(1.5)
        )
        XCTAssertTrue(changed.stableURLs.isEmpty)
        XCTAssertEqual(changed.unstableCount, 1)

        let settled = try tracker.evaluate(
            in: inbox.directoryURL,
            now: now.addingTimeInterval(2.75)
        )
        XCTAssertEqual(settled.stableURLs.map(\.path), [folder.standardizedFileURL.path])
    }

    func testUnstableItemsAreNotRemoved() throws {
        let (documents, inbox) = try makeInbox()
        let file = try documents.write("Import/Episode.m4a", bytes: 16)
        let now = Date().addingTimeInterval(10)
        try setModificationDate(now.addingTimeInterval(-10), for: file)

        let tracker = ImportInboxStability()
        let result = try tracker.evaluate(in: inbox.directoryURL, now: now)

        XCTAssertTrue(result.stableURLs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try inbox.pendingURLs().count, 1)
    }
}
