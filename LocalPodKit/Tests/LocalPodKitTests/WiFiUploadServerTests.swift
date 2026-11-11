import Foundation
import XCTest
@testable import LocalPodKit

final class WiFiUploadServerTests: XCTestCase {
    private var temporary: TemporaryDirectory?
    private var store: WiFiUploadStore?
    private var server: WiFiUploadServer?
    private var eventTask: Task<Void, Never>?

    private static let contentSecurityPolicy =
        "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; "
        + "connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'"

    override func tearDown() async throws {
        if let server {
            await server.stop()
        }
        eventTask?.cancel()
        eventTask = nil
        server = nil
        store = nil
        temporary = nil
    }

    func testLoopbackUploadFlowAndPageSecurity() async throws {
        let pin = "123456"
        let (server, store, baseURL) = try await startServer(pin: pin)
        let collector = WiFiEventCollector()
        eventTask = Task {
            for await event in server.events {
                collector.append(event)
            }
        }

        // The response from start() is synchronous with the ready event, but
        // the collector may not have consumed it yet.
        let sawReady = await waitUntil(timeout: 5) { collector.readyInfo != nil }
        XCTAssertTrue(sawReady)

        let currentPIN = await server.currentPIN()
        XCTAssertEqual(currentPIN, pin)

        let activeDirectories = try FileManager.default.contentsOfDirectory(
            at: store.rootURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        XCTAssertEqual(activeDirectories.count, 1)
        let activeDirectory = try XCTUnwrap(activeDirectories.first)
        XCTAssertTrue(try directoryContents(activeDirectory).isEmpty)

        let (page, pageData) = try await request(baseURL: baseURL, path: "/")
        XCTAssertEqual(page.statusCode, 200)
        XCTAssertEqual(
            page.value(forHTTPHeaderField: "Content-Type"),
            "text/html; charset=utf-8"
        )
        XCTAssertEqual(
            page.value(forHTTPHeaderField: "Content-Security-Policy"),
            Self.contentSecurityPolicy
        )
        XCTAssertEqual(
            page.value(forHTTPHeaderField: "X-Content-Type-Options"),
            "nosniff"
        )
        XCTAssertEqual(
            page.value(forHTTPHeaderField: "Cache-Control"),
            "no-store"
        )
        XCTAssertEqual(
            page.value(forHTTPHeaderField: "Referrer-Policy"),
            "no-referrer"
        )

        let html = try XCTUnwrap(String(data: pageData, encoding: .utf8))
        XCTAssertTrue(html.contains("LocalPod Wi-Fi Upload"))
        XCTAssertTrue(html.contains("webkitdirectory"))
        XCTAssertFalse(html.contains(pin))
        XCTAssertFalse(html.contains("http://"))

        let (missingPIN, _) = try await request(
            baseURL: baseURL,
            path: "/api/verify"
        )
        XCTAssertEqual(missingPIN.statusCode, 401)

        let (verified, _) = try await request(
            baseURL: baseURL,
            path: "/api/verify",
            headers: ["X-LocalPod-Pin": pin]
        )
        XCTAssertEqual(verified.statusCode, 204)

        let (wrongMethod, _) = try await request(
            baseURL: baseURL,
            path: "/api/upload",
            headers: ["X-LocalPod-Pin": pin]
        )
        XCTAssertEqual(wrongMethod.statusCode, 405)

        // Traversal must be rejected at the HTTP boundary before any file is
        // created; the store must not escape the session directory.
        let (badPath, _) = try await request(
            baseURL: baseURL,
            path: "/api/upload",
            method: "POST",
            headers: [
                "X-LocalPod-Pin": pin,
                "X-LocalPod-Path": "..%2Fescape.mp3",
                "Content-Length": "0"
            ],
            body: Data()
        )
        XCTAssertEqual(badPath.statusCode, 400)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.rootURL.appendingPathComponent("escape.mp3").path
            )
        )

        let payload = Data("hello localpod".utf8)
        let (upload, uploadData) = try await request(
            baseURL: baseURL,
            path: "/api/upload",
            method: "POST",
            headers: [
                "X-LocalPod-Pin": pin,
                "X-LocalPod-Path": "Course/01%20Lesson.mp3",
                "Content-Length": "\(payload.count)",
                "Content-Type": "application/octet-stream"
            ],
            body: payload
        )
        XCTAssertEqual(upload.statusCode, 201)
        let uploadJSON = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: uploadData) as? [String: Any]
        )
        XCTAssertEqual(uploadJSON["ok"] as? Bool, true)
        XCTAssertEqual(
            (uploadJSON["bytes"] as? NSNumber)?.int64Value,
            Int64(payload.count)
        )
        XCTAssertEqual(uploadJSON["file"] as? String, "01 Lesson.mp3")

        let sawFinished = await waitUntil(timeout: 5) {
            collector.finished.count == 1
        }
        XCTAssertTrue(sawFinished)
        XCTAssertEqual(collector.finished.first?.name, "Course/01 Lesson.mp3")
        XCTAssertEqual(collector.finished.first?.bytes, Int64(payload.count))

        let (complete, _) = try await request(
            baseURL: baseURL,
            path: "/api/complete",
            method: "POST",
            headers: [
                "X-LocalPod-Pin": pin,
                "Content-Length": "0"
            ],
            body: Data()
        )
        XCTAssertEqual(complete.statusCode, 200)

        let sawCompleted = await waitUntil(timeout: 5) {
            collector.completed != nil
        }
        XCTAssertTrue(sawCompleted)
        let completed = try XCTUnwrap(collector.completed)
        XCTAssertEqual(completed.suggestedCollectionName, "Course")
        XCTAssertEqual(completed.directoryURL.lastPathComponent, "Course")

        let uploadedFile = completed.directoryURL
            .appendingPathComponent("01 Lesson.mp3")
        XCTAssertEqual(try Data(contentsOf: uploadedFile), payload)

        let marker = completed.directoryURL
            .deletingLastPathComponent()
            .appendingPathComponent(".localpod-complete")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))

        let pending = try store.pendingCompletedSessions()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.sessionID, completed.sessionID)

        // A fresh session is ready for the next batch.
        let rootDirectories = try FileManager.default.contentsOfDirectory(
            at: store.rootURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        XCTAssertEqual(rootDirectories.count, 2)
    }

    func testRateLimitBlocksAfterEightBadPINs() async throws {
        let pin = "654321"
        let (_, _, baseURL) = try await startServer(pin: pin)

        for _ in 0..<8 {
            let (response, _) = try await request(
                baseURL: baseURL,
                path: "/api/verify",
                headers: ["X-LocalPod-Pin": "000000"]
            )
            XCTAssertEqual(response.statusCode, 401)
        }

        let (limited, _) = try await request(
            baseURL: baseURL,
            path: "/api/verify",
            headers: ["X-LocalPod-Pin": pin]
        )
        XCTAssertEqual(limited.statusCode, 429)
    }

    // MARK: Helpers

    private func startServer(
        pin: String
    ) async throws -> (WiFiUploadServer, WiFiUploadStore, URL) {
        let temporary = try TemporaryDirectory()
        self.temporary = temporary
        let store = WiFiUploadStore(
            rootURL: temporary.url.appendingPathComponent("WiFiUploads", isDirectory: true)
        )
        self.store = store
        let server = WiFiUploadServer(store: store, pin: pin, port: 0)
        self.server = server

        let info = try await server.start()
        let baseURL = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(info.port)/")
        )
        XCTAssertEqual(Int(info.port), baseURL.port)
        return (server, store, baseURL)
    }

    private func request(
        baseURL: URL,
        path: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> (response: HTTPURLResponse, data: Data) {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw ServerTestError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServerTestError.notHTTP
        }
        return (http, data)
    }

    private func directoryContents(_ directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
    }

    private func waitUntil(
        timeout: TimeInterval,
        _ condition: @escaping @Sendable () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}

private enum ServerTestError: Error {
    case invalidURL
    case notHTTP
}

private final class WiFiEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [WiFiUploadServerEvent] = []

    func append(_ event: WiFiUploadServerEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    private var snapshot: [WiFiUploadServerEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var readyInfo: WiFiUploadServerInfo? {
        for event in snapshot {
            if case .ready(let info) = event { return info }
        }
        return nil
    }

    var completed: WiFiCompletedUpload? {
        for event in snapshot {
            if case .sessionCompleted(let upload) = event { return upload }
        }
        return nil
    }

    var finished: [(name: String, bytes: Int64)] {
        snapshot.compactMap { event in
            guard case .uploadFinished(let name, let bytes) = event else {
                return nil
            }
            return (name, bytes)
        }
    }
}
