import Foundation
import XCTest
@testable import LocalPodKit

final class WiFiUploadStoreTests: XCTestCase {
    private var temporary: TemporaryDirectory!
    private var store: WiFiUploadStore!
    private var session: WiFiUploadSession!

    override func setUpWithError() throws {
        temporary = try TemporaryDirectory()
        store = WiFiUploadStore(
            rootURL: temporary.url.appendingPathComponent("WiFiUploads", isDirectory: true)
        )
        session = try store.createSession()
    }

    override func tearDownWithError() throws {
        session = nil
        store = nil
        temporary = nil
    }

    // MARK: Path safety

    func testRejectsUnsafePathsBeforeCreatingAnything() throws {
        let invalidPaths = [
            "",
            "/absolute.mp3",
            "../escape.mp3",
            "a/../escape.mp3",
            "a/./b.mp3",
            "a\\b.mp3",
            ".hidden.mp3",
            "a/.hidden/b.mp3",
            "a:b.mp3",
            "a//b.mp3",
            "a/",
            "a/\u{0}b.mp3",
            "a/\nb.mp3",
            String(repeating: "a", count: 201) + ".mp3",
            (0..<17).map { _ in "d" }.joined(separator: "/") + "/file.mp3",
            (0..<6).map { _ in String(repeating: "a", count: 200) }
                .joined(separator: "/") + "/x.mp3"
        ]

        for path in invalidPaths {
            XCTAssertThrowsError(
                try store.beginFile(
                    sessionID: session.id,
                    relativePath: path,
                    expectedBytes: 0
                ),
                "Expected rejection for \(path.debugDescription)"
            ) { error in
                XCTAssertEqual(
                    error as? WiFiUploadError,
                    .invalidPath,
                    "Wrong error for \(path.debugDescription)"
                )
            }
        }

        let rootEntries = try FileManager.default.contentsOfDirectory(
            at: store.rootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(rootEntries.count, 1)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: session.directoryURL,
                includingPropertiesForKeys: nil
            ).count,
            0
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: temporary.url.appendingPathComponent("escape.mp3").path
            )
        )
    }

    func testAcceptsUnicodeAndNestedPaths() throws {
        let unicodeData = Data("unicode".utf8)
        let unicodeURL = try upload(
            path: "课程/第 1 课.mp3",
            data: unicodeData
        )
        XCTAssertEqual(unicodeURL.lastPathComponent, "第 1 课.mp3")
        XCTAssertEqual(
            unicodeURL.deletingLastPathComponent().lastPathComponent,
            "课程"
        )
        XCTAssertEqual(try Data(contentsOf: unicodeURL), unicodeData)

        let nestedData = Data("nested".utf8)
        let nestedURL = try upload(path: "a/b/c/file.m4a", data: nestedData)
        XCTAssertEqual(try Data(contentsOf: nestedURL), nestedData)
        XCTAssertTrue(nestedURL.path.hasPrefix(session.directoryURL.path + "/"))

        // Exactly at the limits is allowed.
        let component = String(repeating: "b", count: 200)
        let edge = try store.beginFile(
            sessionID: session.id,
            relativePath: component,
            expectedBytes: 0
        )
        XCTAssertEqual(edge.expectedBytes, 0)
        edge.cancel()

        let depth16 = (0..<15).map { _ in "d" }.joined(separator: "/") + "/f.mp3"
        let deepSink = try store.beginFile(
            sessionID: session.id,
            relativePath: depth16,
            expectedBytes: 0
        )
        deepSink.cancel()
    }

    func testEmptyFileIsAllowed() throws {
        let url = try upload(path: "empty.mp3", data: Data())
        XCTAssertEqual(try Data(contentsOf: url), Data())
    }

    // MARK: Limits

    func testPerFileLimit() throws {
        let limitedStore = WiFiUploadStore(
            rootURL: temporary.url.appendingPathComponent("limited-file", isDirectory: true),
            limits: WiFiUploadLimits(maxFileBytes: 10)
        )
        let limitedSession = try limitedStore.createSession()

        XCTAssertThrowsError(
            try limitedStore.beginFile(
                sessionID: limitedSession.id,
                relativePath: "big.mp3",
                expectedBytes: 11
            )
        ) { error in
            XCTAssertEqual(error as? WiFiUploadError, .fileTooLarge)
        }

        XCTAssertThrowsError(
            try limitedStore.beginFile(
                sessionID: limitedSession.id,
                relativePath: "negative.mp3",
                expectedBytes: -1
            )
        ) { error in
            XCTAssertEqual(error as? WiFiUploadError, .invalidByteCount)
        }

        let sink = try limitedStore.beginFile(
            sessionID: limitedSession.id,
            relativePath: "ok.mp3",
            expectedBytes: 10
        )
        try sink.append(Data(repeating: 1, count: 10))
        _ = try sink.finish()
    }

    func testCumulativeLimitIncludesReservedBytes() throws {
        let limitedStore = WiFiUploadStore(
            rootURL: temporary.url.appendingPathComponent("limited-total", isDirectory: true),
            limits: WiFiUploadLimits(maxFileBytes: 100, maxTotalBytes: 150)
        )
        let limitedSession = try limitedStore.createSession()

        let first = try limitedStore.beginFile(
            sessionID: limitedSession.id,
            relativePath: "a.mp3",
            expectedBytes: 100
        )
        try first.append(Data(repeating: 3, count: 100))
        _ = try first.finish()

        XCTAssertThrowsError(
            try limitedStore.beginFile(
                sessionID: limitedSession.id,
                relativePath: "b.mp3",
                expectedBytes: 51
            )
        ) { error in
            XCTAssertEqual(error as? WiFiUploadError, .totalTooLarge)
        }

        // In-flight reservations also count against the total.
        let reservedStore = WiFiUploadStore(
            rootURL: temporary.url.appendingPathComponent("limited-reserved", isDirectory: true),
            limits: WiFiUploadLimits(maxFileBytes: 100, maxTotalBytes: 150)
        )
        let reservedSession = try reservedStore.createSession()
        let inFlight = try reservedStore.beginFile(
            sessionID: reservedSession.id,
            relativePath: "a.mp3",
            expectedBytes: 80
        )
        XCTAssertThrowsError(
            try reservedStore.beginFile(
                sessionID: reservedSession.id,
                relativePath: "b.mp3",
                expectedBytes: 80
            )
        ) { error in
            XCTAssertEqual(error as? WiFiUploadError, .totalTooLarge)
        }

        inFlight.cancel()
        let afterCancel = try reservedStore.beginFile(
            sessionID: reservedSession.id,
            relativePath: "b.mp3",
            expectedBytes: 80
        )
        afterCancel.cancel()
    }

    func testFileCountLimitAndCancelReleasesSlot() throws {
        let limitedStore = WiFiUploadStore(
            rootURL: temporary.url.appendingPathComponent("limited-count", isDirectory: true),
            limits: WiFiUploadLimits(maxFiles: 2)
        )
        let limitedSession = try limitedStore.createSession()

        let first = try limitedStore.beginFile(
            sessionID: limitedSession.id,
            relativePath: "a.mp3",
            expectedBytes: 1
        )
        let second = try limitedStore.beginFile(
            sessionID: limitedSession.id,
            relativePath: "b.mp3",
            expectedBytes: 1
        )
        XCTAssertThrowsError(
            try limitedStore.beginFile(
                sessionID: limitedSession.id,
                relativePath: "c.mp3",
                expectedBytes: 1
            )
        ) { error in
            XCTAssertEqual(error as? WiFiUploadError, .tooManyFiles)
        }

        first.cancel()
        let third = try limitedStore.beginFile(
            sessionID: limitedSession.id,
            relativePath: "c.mp3",
            expectedBytes: 1
        )
        second.cancel()
        third.cancel()
    }

    // MARK: Destinations and completion

    func testCollisionGetsSuffixAndNeverOverwrites() throws {
        let firstURL = try upload(path: "a.mp3", data: Data("first".utf8))
        let secondURL = try upload(path: "a.mp3", data: Data("second".utf8))
        let thirdURL = try upload(path: "a.mp3", data: Data("third".utf8))

        XCTAssertEqual(firstURL.lastPathComponent, "a.mp3")
        XCTAssertEqual(secondURL.lastPathComponent, "a-2.mp3")
        XCTAssertEqual(thirdURL.lastPathComponent, "a-3.mp3")
        XCTAssertEqual(try Data(contentsOf: firstURL), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: secondURL), Data("second".utf8))
        XCTAssertEqual(try Data(contentsOf: thirdURL), Data("third".utf8))
    }

    func testCompleteInfersSingleTopLevelFolder() throws {
        _ = try upload(path: "Course/01.mp3", data: Data("1".utf8))
        _ = try upload(path: "Course/sub/02.mp3", data: Data("2".utf8))

        let completed = try store.completeSession(session.id)
        XCTAssertEqual(completed.sessionID, session.id)
        XCTAssertEqual(completed.suggestedCollectionName, "Course")
        XCTAssertEqual(completed.directoryURL.lastPathComponent, "Course")
        XCTAssertEqual(
            completed.directoryURL.deletingLastPathComponent().standardizedFileURL,
            session.directoryURL.standardizedFileURL
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: session.directoryURL
                    .appendingPathComponent(".localpod-complete")
                    .path
            )
        )
        XCTAssertEqual(try Data(contentsOf: completed.directoryURL
            .appendingPathComponent("01.mp3")), Data("1".utf8))
    }

    func testCompleteWithMixedTopLevelReturnsSessionRoot() throws {
        _ = try upload(path: "top.mp3", data: Data("top".utf8))
        _ = try upload(path: "Course/01.mp3", data: Data("1".utf8))

        let completed = try store.completeSession(session.id)
        XCTAssertNil(completed.suggestedCollectionName)
        XCTAssertEqual(
            completed.directoryURL.standardizedFileURL,
            session.directoryURL.standardizedFileURL
        )
    }

    func testCompleteWithSingleTopLevelFileReturnsSessionRoot() throws {
        _ = try upload(path: "only.mp3", data: Data("only".utf8))
        let completed = try store.completeSession(session.id)
        XCTAssertNil(completed.suggestedCollectionName)
        XCTAssertEqual(
            completed.directoryURL.standardizedFileURL,
            session.directoryURL.standardizedFileURL
        )
    }

    func testCompleteEmptyOrInFlightFails() throws {
        let emptySession = try store.createSession()
        XCTAssertThrowsError(try store.completeSession(emptySession.id)) { error in
            XCTAssertEqual(error as? WiFiUploadError, .sessionNotComplete)
        }

        let sink = try store.beginFile(
            sessionID: session.id,
            relativePath: "pending.mp3",
            expectedBytes: 5
        )
        XCTAssertThrowsError(try store.completeSession(session.id)) { error in
            XCTAssertEqual(error as? WiFiUploadError, .sessionNotComplete)
        }
        sink.cancel()
    }

    // MARK: Cleanup and recovery

    func testCleanupRemovesIncompleteAndKeepsCompleted() throws {
        let completedSession = try store.createSession()
        let completedURL = try upload(
            sessionID: completedSession.id,
            path: "Keep/01.mp3",
            data: Data("keep".utf8)
        )
        let completed = try store.completeSession(completedSession.id)
        XCTAssertEqual(completedURL.lastPathComponent, "01.mp3")

        let incompleteSession = try store.createSession()
        _ = try upload(
            sessionID: incompleteSession.id,
            path: "Drop/02.mp3",
            data: Data("drop".utf8)
        )

        try store.cleanupIncompleteSessions()

        XCTAssertNil(store.sessionURL(id: incompleteSession.id))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: completed.directoryURL.appendingPathComponent("01.mp3").path
            )
        )

        let pending = try store.pendingCompletedSessions()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.sessionID, completedSession.id)
        XCTAssertEqual(pending.first?.suggestedCollectionName, "Keep")
    }

    func testInterruptedSessionCleanupRemovesPartials() throws {
        let sink = try store.beginFile(
            sessionID: session.id,
            relativePath: "Interrupted/file.mp3",
            expectedBytes: 10
        )
        try sink.append(Data(repeating: 9, count: 4))

        try store.cleanupIncompleteSessions()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: session.directoryURL.path)
        )
        XCTAssertThrowsError(
            try store.beginFile(
                sessionID: session.id,
                relativePath: "another.mp3",
                expectedBytes: 1
            )
        ) { error in
            XCTAssertEqual(error as? WiFiUploadError, .sessionNotFound)
        }
    }

    func testRemovePartialArtifactsKeepsFinishedFiles() throws {
        let finishedURL = try upload(path: "keep.mp3", data: Data("keep".utf8))
        let sink = try store.beginFile(
            sessionID: session.id,
            relativePath: "partial.mp3",
            expectedBytes: 10
        )
        try sink.append(Data(repeating: 1, count: 5))

        try store.removePartialArtifacts(sessionID: session.id)

        let names = try allNames(below: session.directoryURL)
        XCTAssertFalse(names.contains { $0.hasPrefix(".partial-") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: finishedURL.path))
        sink.cancel()
    }

    func testPendingCompletedSessionsSurviveReopenAndCanBeRemoved() throws {
        _ = try upload(path: "Album/01.mp3", data: Data("a".utf8))
        _ = try store.completeSession(session.id)

        let reopened = WiFiUploadStore(rootURL: store.rootURL)
        let pending = try reopened.pendingCompletedSessions()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.sessionID, session.id)
        XCTAssertEqual(pending.first?.suggestedCollectionName, "Album")

        try reopened.removeSession(session.id)
        XCTAssertTrue(try reopened.pendingCompletedSessions().isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: session.directoryURL.path)
        )
        XCTAssertThrowsError(try reopened.removeSession(session.id)) { error in
            XCTAssertEqual(error as? WiFiUploadError, .sessionNotFound)
        }
    }

    // MARK: Streaming sink

    func testSinkStreamsExactBytesAndIsIdempotentAfterFinish() throws {
        let sink = try store.beginFile(
            sessionID: session.id,
            relativePath: "Stream/data.bin",
            expectedBytes: 6
        )
        try sink.append(Data([1, 2]))
        try sink.append(Data([3, 4]))
        try sink.append(Data([5, 6]))

        let firstFinish = try sink.finish()
        let secondFinish = try sink.finish()
        XCTAssertEqual(firstFinish, secondFinish)
        XCTAssertEqual(try Data(contentsOf: firstFinish), Data([1, 2, 3, 4, 5, 6]))

        sink.cancel()
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstFinish.path))
        XCTAssertThrowsError(try sink.append(Data([7]))) { error in
            XCTAssertEqual(error as? WiFiUploadError, .sinkClosed)
        }
        XCTAssertEqual(try sink.finish(), firstFinish)
    }

    func testSinkMismatchRemovesPartialAndReleasesReservation() throws {
        let sink = try store.beginFile(
            sessionID: session.id,
            relativePath: "Mismatch/file.bin",
            expectedBytes: 5
        )
        try sink.append(Data([1, 2, 3]))

        XCTAssertThrowsError(try sink.finish()) { error in
            XCTAssertEqual(error as? WiFiUploadError, .byteCountMismatch)
        }
        XCTAssertTrue(
            try allNames(below: session.directoryURL)
                .allSatisfy { !$0.hasPrefix(".partial-") }
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: session.directoryURL.appendingPathComponent("Mismatch"),
                includingPropertiesForKeys: nil
            ).count,
            0
        )

        XCTAssertThrowsError(try sink.append(Data([4]))) { error in
            XCTAssertEqual(error as? WiFiUploadError, .sinkClosed)
        }
        XCTAssertThrowsError(try sink.finish()) { error in
            XCTAssertEqual(error as? WiFiUploadError, .sinkClosed)
        }

        // The reservation was released, so the session can accept a new file.
        let retry = try store.beginFile(
            sessionID: session.id,
            relativePath: "Mismatch/file.bin",
            expectedBytes: 5
        )
        try retry.append(Data(repeating: 7, count: 5))
        _ = try retry.finish()
    }

    func testSinkRejectsOversizedAppendAndCancelIsSafe() throws {
        let sink = try store.beginFile(
            sessionID: session.id,
            relativePath: "limits.bin",
            expectedBytes: 3
        )
        try sink.append(Data([1, 2, 3]))
        XCTAssertThrowsError(try sink.append(Data([4]))) { error in
            XCTAssertEqual(error as? WiFiUploadError, .fileTooLarge)
        }
        sink.cancel()
        sink.cancel()

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: session.directoryURL.appendingPathComponent("limits.bin").path
            )
        )
    }

    // MARK: Helpers

    @discardableResult
    private func upload(
        sessionID: UUID? = nil,
        path: String,
        data: Data
    ) throws -> URL {
        let sink = try store.beginFile(
            sessionID: sessionID ?? session.id,
            relativePath: path,
            expectedBytes: Int64(data.count)
        )
        try sink.append(data)
        return try sink.finish()
    }

    private func allNames(below directory: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        var names: [String] = []
        while let url = enumerator.nextObject() as? URL {
            names.append(url.lastPathComponent)
        }
        return names
    }
}

// MARK: - PIN and rate limiting

final class WiFiPINTests: XCTestCase {
    func testGeneratedPinsHaveRequestedLengthAndDigits() {
        for length in [1, 6, 12] {
            let pin = WiFiPIN.generate(length: length)
            XCTAssertEqual(pin.count, length)
            XCTAssertTrue(pin.allSatisfy(\.isNumber))
        }

        XCTAssertEqual(WiFiPIN.generate(length: 0).count, 1)
        XCTAssertEqual(WiFiPIN.generate(length: 200).count, 64)

        let values = Set((0..<20).map { _ in WiFiPIN.generate(length: 6) })
        XCTAssertGreaterThan(values.count, 1)
    }

    func testConstantTimeComparison() {
        XCTAssertTrue(WiFiPIN.constantTimeEquals("123456", "123456"))
        XCTAssertFalse(WiFiPIN.constantTimeEquals("123456", "123457"))
        XCTAssertFalse(WiFiPIN.constantTimeEquals("123", "1234"))
        XCTAssertFalse(WiFiPIN.constantTimeEquals("", "0"))
        XCTAssertTrue(WiFiPIN.constantTimeEquals("", ""))
    }

    func testRateLimiterBlocksAfterEightFailuresAndResetsOnSuccess() {
        let limiter = WiFiPINRateLimiter(maxAttempts: 8, window: 60)
        let start = Date(timeIntervalSince1970: 1_000)

        for _ in 0..<7 {
            limiter.recordFailure(host: "10.0.0.2", at: start)
        }
        XCTAssertFalse(limiter.isLimited(host: "10.0.0.2", at: start))
        XCTAssertFalse(limiter.isLimited(host: "10.0.0.3", at: start))

        limiter.recordFailure(host: "10.0.0.2", at: start)
        XCTAssertTrue(limiter.isLimited(host: "10.0.0.2", at: start))
        XCTAssertFalse(limiter.isLimited(host: "10.0.0.3", at: start))

        limiter.recordSuccess(host: "10.0.0.2")
        XCTAssertFalse(limiter.isLimited(host: "10.0.0.2", at: start))
    }

    func testRateLimiterExpiresFailuresOutsideWindow() {
        let limiter = WiFiPINRateLimiter(maxAttempts: 2, window: 60)
        let start = Date(timeIntervalSince1970: 1_000)

        limiter.recordFailure(host: "host", at: start)
        limiter.recordFailure(host: "host", at: start.addingTimeInterval(30))
        XCTAssertTrue(limiter.isLimited(host: "host", at: start.addingTimeInterval(31)))
        XCTAssertFalse(limiter.isLimited(host: "host", at: start.addingTimeInterval(61)))

        limiter.recordFailure(host: "host", at: start.addingTimeInterval(62))
        XCTAssertTrue(limiter.isLimited(host: "host", at: start.addingTimeInterval(63)))
        XCTAssertFalse(limiter.isLimited(host: "host", at: start.addingTimeInterval(92)))
        XCTAssertFalse(limiter.isLimited(host: "host", at: start.addingTimeInterval(123)))
    }
}

// MARK: - Address policy

final class WiFiNetworkAddressTests: XCTestCase {
    func testAllowsLoopbackPrivateLinkLocalAndULA() {
        let allowed = [
            "127.0.0.1",
            "127.10.20.30",
            "10.0.0.1",
            "10.255.255.254",
            "172.16.0.1",
            "172.31.255.255",
            "192.168.0.1",
            "192.168.255.255",
            "169.254.1.2",
            "::1",
            "fe80::1",
            "fe80::abcd:1234",
            "fc00::1",
            "fd12:3456:789a::1",
            "::ffff:192.168.1.20",
            "::ffff:127.0.0.1",
            "localhost",
            "LOCALHOST",
            "[::1]",
            "fe80::1%en0"
        ]
        for address in allowed {
            XCTAssertTrue(
                WiFiNetworkAddress.isAllowedRemote(address),
                "Expected \(address) to be allowed"
            )
        }
    }

    func testRejectsPublicAndMalformedAddresses() {
        let denied = [
            "8.8.8.8",
            "1.1.1.1",
            "11.0.0.1",
            "172.15.255.255",
            "172.32.0.1",
            "192.169.0.1",
            "169.253.0.1",
            "0.0.0.0",
            "255.255.255.255",
            "::",
            "2001:4860:4860::8888",
            "fec0::1",
            "::ffff:8.8.8.8",
            "example.com",
            "not-an-address",
            ""
        ]
        for address in denied {
            XCTAssertFalse(
                WiFiNetworkAddress.isAllowedRemote(address),
                "Expected \(address) to be rejected"
            )
        }
    }

    func testIPv4ClassificationHelpers() {
        XCTAssertTrue(WiFiNetworkAddress.isLoopbackIPv4("127.0.0.1"))
        XCTAssertFalse(WiFiNetworkAddress.isLoopbackIPv4("10.0.0.1"))
        XCTAssertTrue(WiFiNetworkAddress.isPrivateIPv4("10.1.2.3"))
        XCTAssertTrue(WiFiNetworkAddress.isPrivateIPv4("172.20.0.1"))
        XCTAssertTrue(WiFiNetworkAddress.isPrivateIPv4("192.168.1.1"))
        XCTAssertTrue(WiFiNetworkAddress.isPrivateIPv4("169.254.1.1"))
        XCTAssertFalse(WiFiNetworkAddress.isPrivateIPv4("8.8.8.8"))
        XCTAssertFalse(WiFiNetworkAddress.isPrivateIPv4("127.0.0.1"))
    }

    func testLocalAddressListAlwaysHasAnAllowedAddress() {
        let addresses = WiFiNetworkAddress.localIPv4Addresses()
        XCTAssertFalse(addresses.isEmpty)
        for address in addresses {
            XCTAssertTrue(WiFiNetworkAddress.isAllowedRemote(address))
        }
    }
}

// MARK: - HTTP head parser

final class WiFiHTTPHeadParserTests: XCTestCase {
    func testParsesRequestAndReportsHeaderBoundary() throws {
        let body = Data("hello".utf8)
        var data = Data(
            "POST /api/upload HTTP/1.1\r\nHost: local\r\nX-LocalPod-Pin: 123456\r\nX-LocalPod-Path: Course%2F01.mp3\r\nContent-Length: 5\r\n\r\n"
                .utf8
        )
        let boundary = data.count
        data.append(body)

        let head = try XCTUnwrap(WiFiHTTPHeadParser.parse(data))
        XCTAssertEqual(head.method, "POST")
        XCTAssertEqual(head.target, "/api/upload")
        XCTAssertEqual(head.version, "HTTP/1.1")
        XCTAssertEqual(head.headers["x-localpod-pin"], "123456")
        XCTAssertEqual(head.headers["x-localpod-path"], "Course%2F01.mp3")
        XCTAssertEqual(head.headers["content-length"], "5")
        XCTAssertEqual(head.headerByteCount, boundary)
        XCTAssertEqual(Data(data.dropFirst(head.headerByteCount)), body)
    }

    func testWaitsForHeaderTerminator() throws {
        XCTAssertNil(
            try WiFiHTTPHeadParser.parse(Data("GET / HTTP/1.1\r\nHost: local\r\n".utf8))
        )
    }

    func testRejectsOversizedHeaderBlock() {
        let oversized = Data(repeating: 0x41, count: WiFiHTTPHeadParser.maxHeaderBytes + 1)
        XCTAssertThrowsError(try WiFiHTTPHeadParser.parse(oversized)) { error in
            XCTAssertEqual(error as? WiFiHTTPHeadParseError, .headersTooLarge)
        }
    }

    func testRejectsMalformedAndDuplicateFramingHeaders() {
        let malformed = [
            Data("GET /\r\n\r\n".utf8),
            Data("GET / HTTP/1.1\r\nBadHeader\r\n\r\n".utf8),
            Data("GET / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n".utf8),
            Data("GET / HTTP/2.0\r\n\r\n".utf8),
            Data("GET http://example.com/ HTTP/1.1\r\n\r\n".utf8)
        ]
        for data in malformed {
            XCTAssertThrowsError(try WiFiHTTPHeadParser.parse(data))
        }
    }
}
