import Foundation
import Network

// MARK: - Public server models

public enum WiFiUploadServerEvent: Sendable {
    case ready(WiFiUploadServerInfo)
    case uploadFinished(fileName: String, bytes: Int64)
    case sessionCompleted(WiFiCompletedUpload)
    case failed(String)
}

public struct WiFiUploadServerInfo: Sendable, Equatable {
    public let port: UInt16
    public let urls: [URL]

    public init(port: UInt16, urls: [URL]) {
        self.port = port
        self.urls = urls
    }

    public var primaryURL: URL? {
        urls.first
    }
}

// MARK: - HTTP request head parsing

struct WiFiHTTPHead: Sendable, Equatable {
    let method: String
    let target: String
    let version: String
    let headers: [String: String]
    /// Number of bytes in the original buffer belonging to the head,
    /// including the terminating CRLFCRLF. The rest is body prefix.
    let headerByteCount: Int
}

enum WiFiHTTPHeadParseError: Error, Equatable {
    case malformed
    case headersTooLarge
    case unsupportedVersion
}

enum WiFiHTTPHeadParser {
    static let maxHeaderBytes = 16 * 1024
    private static let terminator = Data("\r\n\r\n".utf8)

    /// Returns nil while the head is incomplete. Throws for malformed or
    /// oversized heads; the 16 KiB limit covers the request line, headers and
    /// terminator, so a body prefix may be arbitrarily larger.
    static func parse(_ data: Data) throws -> WiFiHTTPHead? {
        guard let range = data.range(of: terminator) else {
            if data.count >= maxHeaderBytes {
                throw WiFiHTTPHeadParseError.headersTooLarge
            }
            return nil
        }
        guard range.upperBound <= maxHeaderBytes else {
            throw WiFiHTTPHeadParseError.headersTooLarge
        }

        let headData = data[data.startIndex..<range.lowerBound]
        guard let headString = String(data: headData, encoding: .utf8) else {
            throw WiFiHTTPHeadParseError.malformed
        }

        let lines = headString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw WiFiHTTPHeadParseError.malformed
        }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3 else {
            throw WiFiHTTPHeadParseError.malformed
        }
        let method = String(parts[0])
        let target = String(parts[1])
        let version = String(parts[2])
        guard version == "HTTP/1.1" || version == "HTTP/1.0" else {
            throw WiFiHTTPHeadParseError.unsupportedVersion
        }
        guard !method.isEmpty, target.hasPrefix("/") else {
            throw WiFiHTTPHeadParseError.malformed
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else {
                throw WiFiHTTPHeadParseError.malformed
            }
            let rawName = String(line[..<colon])
            let name = rawName.trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, isToken(name) else {
                throw WiFiHTTPHeadParseError.malformed
            }
            guard value.unicodeScalars.allSatisfy({
                $0.value == 0x09 || ($0.value >= 0x20 && $0.value != 0x7F)
            }) else {
                throw WiFiHTTPHeadParseError.malformed
            }

            if let existing = headers[name] {
                // Reject duplicate framing headers to avoid request smuggling.
                if name == "content-length" || name == "transfer-encoding" || name == "host" {
                    throw WiFiHTTPHeadParseError.malformed
                }
                headers[name] = existing + ", " + value
            } else {
                headers[name] = value
            }
        }
        guard headers.count <= 128 else {
            throw WiFiHTTPHeadParseError.malformed
        }

        return WiFiHTTPHead(
            method: method,
            target: target,
            version: version,
            headers: headers,
            headerByteCount: range.upperBound
        )
    }

    private static func isToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { byte in
            switch byte {
            case 33, 35...39, 42, 43, 45, 46, 48...57, 65...90, 94...122, 124, 126:
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Server

/// A minimal local-network HTTP/1.1 upload server backed by `NWListener`.
///
/// One request is handled per connection (Connection: close). Requests are
/// serialized after authentication so a single active session/sink is
/// unambiguous. The server never serves or lists stored files.
public actor WiFiUploadServer {
    public nonisolated let events: AsyncStream<WiFiUploadServerEvent>

    private nonisolated let eventContinuation: AsyncStream<WiFiUploadServerEvent>.Continuation
    private let store: WiFiUploadStore
    private let rateLimiter: WiFiPINRateLimiter
    private let requestGate = WiFiRequestGate()
    private let connectionQueue = DispatchQueue(label: "com.localpod.wifi-upload.server")
    private let requestedPort: UInt16
    private var pin: String

    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var activeSession: WiFiUploadSession?
    private var activeSink: WiFiUploadFileSink?
    private var info: WiFiUploadServerInfo?
    private var isRunning = false
    private var isStarting = false

    private static let connectionIdleTimeout: TimeInterval = 30
    private static let maxConnections = 32
    private static let bodyChunkBytes = 256 * 1024
    private static let headerReadBytes = 64 * 1024

    public init(store: WiFiUploadStore, pin: String, port: UInt16 = 0) {
        self.store = store
        self.pin = pin
        self.requestedPort = port
        self.rateLimiter = WiFiPINRateLimiter()
        let (stream, continuation) = AsyncStream<WiFiUploadServerEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(256)
        )
        self.events = stream
        self.eventContinuation = continuation
    }

    /// Convenience initializer that generates a fresh six-digit PIN.
    public init(store: WiFiUploadStore, port: UInt16 = 0) {
        self.init(store: store, pin: WiFiPIN.generate(length: 6), port: port)
    }

    deinit {
        eventContinuation.finish()
    }

    public func currentPIN() -> String {
        pin
    }

    public func serverInfo() -> WiFiUploadServerInfo? {
        info
    }

    // MARK: Lifecycle

    public func start() async throws -> WiFiUploadServerInfo {
        if isRunning, let info {
            return info
        }
        guard !isStarting else {
            throw WiFiUploadError.serverUnavailable
        }
        isStarting = true
        defer { isStarting = false }

        var createdSession: WiFiUploadSession?
        do {
            try store.cleanupIncompleteSessions()
            let session = try store.createSession()
            createdSession = session
            activeSession = session

            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let endpointPort: NWEndpoint.Port = requestedPort == 0
                ? .any
                : (NWEndpoint.Port(rawValue: requestedPort) ?? .any)

            let listener: NWListener
            do {
                listener = try NWListener(using: parameters, on: endpointPort)
            } catch {
                throw WiFiUploadError.serverUnavailable
            }
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                guard let self else {
                    connection.cancel()
                    return
                }
                Task { await self.accept(connection) }
            }

            let (stateStream, stateContinuation) = AsyncStream<Result<UInt16, WiFiUploadError>>
                .makeStream(bufferingPolicy: .bufferingNewest(1))
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    if let port = listener?.port?.rawValue {
                        stateContinuation.yield(.success(port))
                    } else {
                        stateContinuation.yield(.failure(.serverUnavailable))
                    }
                    stateContinuation.finish()
                case .failed, .cancelled:
                    stateContinuation.yield(.failure(.serverUnavailable))
                    stateContinuation.finish()
                default:
                    break
                }
            }

            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                stateContinuation.finish()
            }
            defer { timeoutTask.cancel() }

            listener.start(queue: connectionQueue)

            guard let readyResult = await Self.firstState(from: stateStream) else {
                throw WiFiUploadError.serverUnavailable
            }
            let readyPort: UInt16
            switch readyResult {
            case .success(let port) where port != 0:
                readyPort = port
            default:
                throw WiFiUploadError.serverUnavailable
            }

            guard isStarting else {
                throw WiFiUploadError.serverUnavailable
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .cancelled:
                    Task { await self?.listenerDidFail() }
                default:
                    break
                }
            }

            let serverInfo = Self.makeServerInfo(port: readyPort)
            info = serverInfo
            isRunning = true
            eventContinuation.yield(.ready(serverInfo))
            return serverInfo
        } catch {
            listener?.stateUpdateHandler = nil
            listener?.cancel()
            listener = nil
            if let createdSession {
                try? store.removeSession(createdSession.id)
            }
            activeSession = nil
            activeSink = nil
            info = nil
            isRunning = false

            let wifiError = (error as? WiFiUploadError) ?? .serverUnavailable
            eventContinuation.yield(.failed(Self.localizedMessage(for: wifiError)))
            throw wifiError
        }
    }

    public func stop() {
        guard isRunning || isStarting || listener != nil else { return }
        isRunning = false
        isStarting = false

        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil

        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()

        activeSink?.cancel()
        activeSink = nil

        if let session = activeSession {
            try? store.removePartialArtifacts(sessionID: session.id)
            if !store.containsUploadedFiles(sessionID: session.id) {
                try? store.removeSession(session.id)
            }
        }
        activeSession = nil
        info = nil
    }

    /// A listener failure after startup leaves the server unusable. Tear down
    /// cleanly and let the app show an error; completed sessions are kept.
    private func listenerDidFail() {
        guard isRunning else { return }
        stop()
        eventContinuation.yield(
            .failed(LocalPodLocalization.string("error.wifi.serverUnavailable"))
        )
    }

    // MARK: Connection handling

    private func accept(_ connection: NWConnection) {
        guard isRunning else {
            connection.cancel()
            return
        }
        guard connections.count < Self.maxConnections else {
            connection.cancel()
            return
        }

        let id = UUID()
        connections[id] = connection
        connection.start(queue: connectionQueue)
        Task { await self.process(connection, id: id) }
    }

    private func process(_ connection: NWConnection, id: UUID) async {
        defer {
            connections.removeValue(forKey: id)
            connection.cancel()
        }
        guard isRunning else { return }

        let watchdog = WiFiConnectionWatchdog(
            interval: Self.connectionIdleTimeout,
            queue: connectionQueue
        ) {
            connection.cancel()
        }
        defer { watchdog.disarm() }

        guard let remoteHost = Self.remoteHost(for: connection),
              WiFiNetworkAddress.isAllowedRemote(remoteHost) else {
            await send(.error(status: 403, code: "forbiddenNetwork"), on: connection)
            return
        }

        var buffer = Data()
        var head: WiFiHTTPHead?
        while head == nil {
            watchdog.kick()
            let chunk: Data
            do {
                (chunk, _) = try await Self.receive(connection, maximumLength: Self.headerReadBytes)
            } catch {
                return
            }
            guard !chunk.isEmpty else {
                await send(.error(status: 400, code: "invalidRequest"), on: connection)
                return
            }
            buffer.append(chunk)

            do {
                head = try WiFiHTTPHeadParser.parse(buffer)
            } catch let error as WiFiHTTPHeadParseError {
                let status = error == .headersTooLarge ? 431 : 400
                await send(.error(status: status, code: "invalidRequest"), on: connection)
                return
            } catch {
                await send(.error(status: 400, code: "invalidRequest"), on: connection)
                return
            }
        }

        guard let head else { return }
        let bodyPrefix = Data(buffer.dropFirst(head.headerByteCount))

        var path = head.target
        if let end = path.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            path = String(path[..<end])
        }
        guard path.hasPrefix("/") else {
            await send(.error(status: 400, code: "invalidRequest"), on: connection)
            return
        }

        if path == "/" || path == "/index.html" {
            guard head.method == "GET" else {
                await send(
                    .text(status: 405, body: "Method Not Allowed", allow: "GET"),
                    on: connection
                )
                return
            }
            await send(.html(WiFiUploadPage.html), on: connection)
            return
        }

        let knownAPIPaths: Set<String> = ["/api/verify", "/api/upload", "/api/complete"]
        guard path.hasPrefix("/api/") else {
            await send(.error(status: 404, code: "notFound"), on: connection)
            return
        }
        guard knownAPIPaths.contains(path) else {
            await send(.error(status: 404, code: "notFound"), on: connection)
            return
        }

        if rateLimiter.isLimited(host: remoteHost) {
            await send(.error(status: 429, code: "rateLimited"), on: connection)
            return
        }
        guard let candidate = head.headers["x-localpod-pin"],
              WiFiPIN.constantTimeEquals(candidate, pin) else {
            rateLimiter.recordFailure(host: remoteHost)
            await send(.error(status: 401, code: "unauthorized"), on: connection)
            return
        }
        rateLimiter.recordSuccess(host: remoteHost)

        switch path {
        case "/api/verify":
            guard head.method == "GET" else {
                await send(
                    .error(status: 405, code: "methodNotAllowed", allow: "GET"),
                    on: connection
                )
                return
            }
            await send(.empty(status: 204), on: connection)

        case "/api/upload":
            await handleUpload(
                connection: connection,
                head: head,
                bodyPrefix: bodyPrefix,
                watchdog: watchdog
            )

        case "/api/complete":
            await handleComplete(
                connection: connection,
                head: head,
                bodyPrefix: bodyPrefix
            )

        default:
            await send(.error(status: 404, code: "notFound"), on: connection)
        }
    }

    private func handleUpload(
        connection: NWConnection,
        head: WiFiHTTPHead,
        bodyPrefix: Data,
        watchdog: WiFiConnectionWatchdog
    ) async {
        guard head.method == "POST" else {
            await send(
                .error(status: 405, code: "methodNotAllowed", allow: "POST"),
                on: connection
            )
            return
        }
        guard head.headers["transfer-encoding"] == nil else {
            await send(.error(status: 501, code: "chunkedUnsupported"), on: connection)
            return
        }
        guard let lengthText = head.headers["content-length"] else {
            await send(.error(status: 411, code: "lengthRequired"), on: connection)
            return
        }
        guard let contentLength = Int64(lengthText), contentLength >= 0 else {
            await send(.error(status: 400, code: "invalidByteCount"), on: connection)
            return
        }
        guard let encodedPath = head.headers["x-localpod-path"],
              let decodedPath = encodedPath.removingPercentEncoding,
              !decodedPath.isEmpty else {
            await send(.error(status: 400, code: "invalidPath"), on: connection)
            return
        }

        await requestGate.acquire()
        defer { Task { await requestGate.release() } }

        guard let session = activeSession else {
            await send(.error(status: 503, code: "serverUnavailable"), on: connection)
            return
        }
        guard activeSink == nil else {
            await send(.error(status: 409, code: "sinkClosed"), on: connection)
            return
        }

        let sink: WiFiUploadFileSink
        do {
            sink = try store.beginFile(
                sessionID: session.id,
                relativePath: decodedPath,
                expectedBytes: contentLength
            )
        } catch let error as WiFiUploadError {
            await send(
                .error(status: Self.status(for: error), code: Self.code(for: error)),
                on: connection
            )
            return
        } catch {
            await send(.error(status: 500, code: "writeFailed"), on: connection)
            return
        }

        activeSink = sink
        defer { activeSink = nil }

        var received: Int64 = 0
        do {
            if !bodyPrefix.isEmpty {
                guard Int64(bodyPrefix.count) <= contentLength else {
                    throw WiFiUploadError.byteCountMismatch
                }
                try sink.append(bodyPrefix)
                received += Int64(bodyPrefix.count)
            }

            while received < contentLength {
                watchdog.kick()
                let (chunk, _) = try await Self.receive(
                    connection,
                    maximumLength: Self.bodyChunkBytes
                )
                guard !chunk.isEmpty else {
                    throw WiFiUploadError.byteCountMismatch
                }
                guard Int64(chunk.count) <= contentLength - received else {
                    throw WiFiUploadError.byteCountMismatch
                }
                try sink.append(chunk)
                received += Int64(chunk.count)
            }
        } catch let error as WiFiUploadError {
            sink.cancel()
            await send(
                .error(status: Self.status(for: error), code: Self.code(for: error)),
                on: connection
            )
            return
        } catch {
            // Connection failed or the watchdog cancelled it. Remove the
            // partial file and drop the request without a response.
            sink.cancel()
            return
        }

        watchdog.disarm()

        do {
            let finalURL = try sink.finish()
            eventContinuation.yield(
                .uploadFinished(fileName: decodedPath, bytes: received)
            )
            let body = Self.jsonData([
                "ok": true,
                "file": finalURL.lastPathComponent,
                "bytes": received
            ])
            await send(.json(status: 201, body: body), on: connection)
        } catch let error as WiFiUploadError {
            await send(
                .error(status: Self.status(for: error), code: Self.code(for: error)),
                on: connection
            )
        } catch {
            await send(.error(status: 500, code: "writeFailed"), on: connection)
        }
    }

    private func handleComplete(
        connection: NWConnection,
        head: WiFiHTTPHead,
        bodyPrefix: Data
    ) async {
        guard head.method == "POST" else {
            await send(
                .error(status: 405, code: "methodNotAllowed", allow: "POST"),
                on: connection
            )
            return
        }
        guard head.headers["transfer-encoding"] == nil else {
            await send(.error(status: 501, code: "chunkedUnsupported"), on: connection)
            return
        }
        guard let lengthText = head.headers["content-length"] else {
            await send(.error(status: 411, code: "lengthRequired"), on: connection)
            return
        }
        guard let length = Int64(lengthText), length == 0, bodyPrefix.isEmpty else {
            await send(.error(status: 400, code: "invalidByteCount"), on: connection)
            return
        }

        await requestGate.acquire()
        defer { Task { await requestGate.release() } }

        guard let session = activeSession else {
            await send(.error(status: 409, code: "sessionMissing"), on: connection)
            return
        }
        guard activeSink == nil else {
            await send(.error(status: 409, code: "sinkClosed"), on: connection)
            return
        }

        do {
            let completed = try store.completeSession(session.id)
            eventContinuation.yield(.sessionCompleted(completed))

            // Start the next batch immediately. If this fails the completion
            // still succeeded, so the client gets a success response; the next
            // upload will retry session creation through the server's state.
            if let next = try? store.createSession() {
                activeSession = next
            } else {
                activeSession = nil
            }

            await send(
                .json(status: 200, body: Self.jsonData(["ok": true])),
                on: connection
            )
        } catch let error as WiFiUploadError {
            await send(
                .error(status: Self.status(for: error), code: Self.code(for: error)),
                on: connection
            )
        } catch {
            await send(.error(status: 500, code: "writeFailed"), on: connection)
        }
    }

    // MARK: Networking helpers

    nonisolated private static func receive(
        _ connection: NWConnection,
        maximumLength: Int
    ) async throws -> (Data, Bool) {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<(Data, Bool), Error>) in
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: maximumLength
            ) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data ?? Data(), isComplete))
                }
            }
        }
    }

    nonisolated private static func remoteHost(for connection: NWConnection) -> String? {
        let endpoint = connection.currentPath?.remoteEndpoint ?? connection.endpoint
        guard case .hostPort(let host, _) = endpoint else { return nil }
        let value = WiFiNetworkAddress.hostString(host)
        return value.isEmpty ? nil : value
    }

    nonisolated private static func firstState(
        from stream: AsyncStream<Result<UInt16, WiFiUploadError>>
    ) async -> Result<UInt16, WiFiUploadError>? {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    nonisolated private static func makeServerInfo(port: UInt16) -> WiFiUploadServerInfo {
        var urls = WiFiNetworkAddress.localIPv4Addresses().compactMap {
            makeURL(host: $0, port: port)
        }
        if urls.isEmpty {
            urls = [makeURL(host: "127.0.0.1", port: port)].compactMap { $0 }
        }
        return WiFiUploadServerInfo(port: port, urls: urls)
    }

    nonisolated private static func makeURL(host: String, port: UInt16) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = "/"
        return components.url
    }

    // MARK: Responses

    private func send(_ response: WiFiHTTPResponse, on connection: NWConnection) async {
        let data = response.serialized()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: data, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
        connection.cancel()
    }

    nonisolated private static func jsonData(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: []))
            ?? Data("{}".utf8)
    }

    nonisolated private static func localizedMessage(for error: WiFiUploadError) -> String {
        error.errorDescription
            ?? LocalPodLocalization.string("error.wifi.serverUnavailable")
    }

    nonisolated private static func code(for error: WiFiUploadError) -> String {
        switch error {
        case .invalidPath: "invalidPath"
        case .tooManyFiles: "tooManyFiles"
        case .fileTooLarge: "fileTooLarge"
        case .totalTooLarge: "totalTooLarge"
        case .sessionNotFound: "sessionMissing"
        case .sessionNotComplete: "sessionNotComplete"
        case .sessionAlreadyCompleted: "sessionAlreadyCompleted"
        case .byteCountMismatch: "byteCountMismatch"
        case .invalidByteCount: "invalidByteCount"
        case .cannotCreateDirectory: "cannotCreateDirectory"
        case .writeFailed: "writeFailed"
        case .sinkClosed: "sinkClosed"
        case .serverUnavailable: "serverUnavailable"
        case .unauthorized: "unauthorized"
        case .rateLimited: "rateLimited"
        case .forbiddenNetwork: "forbiddenNetwork"
        case .requestTimeout: "requestTimeout"
        }
    }

    nonisolated private static func status(for error: WiFiUploadError) -> Int {
        switch error {
        case .invalidPath, .invalidByteCount, .byteCountMismatch:
            400
        case .tooManyFiles, .fileTooLarge, .totalTooLarge:
            413
        case .sessionNotFound, .sessionNotComplete, .sessionAlreadyCompleted, .sinkClosed:
            409
        case .cannotCreateDirectory, .writeFailed:
            500
        case .serverUnavailable:
            503
        case .unauthorized:
            401
        case .rateLimited:
            429
        case .forbiddenNetwork:
            403
        case .requestTimeout:
            408
        }
    }
}

// MARK: - Serial request gate

/// Serializes stateful routes (upload/complete) without blocking verification
/// or the static page. The lock stays held while a waiter is resumed.
private actor WiFiRequestGate {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            locked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

// MARK: - Idle watchdog

/// Cancels a connection when no request bytes arrive for `interval` seconds.
/// `kick()` is called before each receive; `disarm()` stops the timer while the
/// request is processed locally.
private final class WiFiConnectionWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private let queue: DispatchQueue
    private let interval: TimeInterval
    private let action: @Sendable () -> Void
    private var workItem: DispatchWorkItem?

    init(
        interval: TimeInterval,
        queue: DispatchQueue,
        action: @escaping @Sendable () -> Void
    ) {
        self.interval = interval
        self.queue = queue
        self.action = action
    }

    func kick() {
        lock.lock()
        workItem?.cancel()
        let item = DispatchWorkItem(block: action)
        workItem = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + interval, execute: item)
    }

    func disarm() {
        lock.lock()
        workItem?.cancel()
        workItem = nil
        lock.unlock()
    }
}

// MARK: - HTTP response

private struct WiFiHTTPResponse: Sendable {
    let status: Int
    let contentType: String?
    let body: Data
    var additionalHeaders: [(String, String)] = []

    static func html(_ html: String) -> WiFiHTTPResponse {
        WiFiHTTPResponse(
            status: 200,
            contentType: "text/html; charset=utf-8",
            body: Data(html.utf8)
        )
    }

    static func json(status: Int, body: Data) -> WiFiHTTPResponse {
        WiFiHTTPResponse(
            status: status,
            contentType: "application/json; charset=utf-8",
            body: body
        )
    }

    static func empty(status: Int) -> WiFiHTTPResponse {
        WiFiHTTPResponse(status: status, contentType: nil, body: Data())
    }

    static func text(
        status: Int,
        body: String,
        allow: String? = nil
    ) -> WiFiHTTPResponse {
        WiFiHTTPResponse(
            status: status,
            contentType: "text/plain; charset=utf-8",
            body: Data(body.utf8),
            additionalHeaders: allow.map { [("Allow", $0)] } ?? []
        )
    }

    static func error(
        status: Int,
        code: String,
        allow: String? = nil
    ) -> WiFiHTTPResponse {
        WiFiHTTPResponse(
            status: status,
            contentType: "application/json; charset=utf-8",
            body: (try? JSONSerialization.data(
                withJSONObject: ["ok": false, "error": code],
                options: []
            )) ?? Data("{}".utf8),
            additionalHeaders: allow.map { [("Allow", $0)] } ?? []
        )
    }

    func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        head += "Connection: close\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "X-Content-Type-Options: nosniff\r\n"
        head += "Referrer-Policy: no-referrer\r\n"
        head += "X-Frame-Options: DENY\r\n"
        head += "Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; "
        head += "script-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; "
        head += "base-uri 'none'; form-action 'none'\r\n"
        head += "Content-Length: \(body.count)\r\n"
        if let contentType {
            head += "Content-Type: \(contentType)\r\n"
        }
        for (name, value) in additionalHeaders {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 408: "Request Timeout"
        case 409: "Conflict"
        case 411: "Length Required"
        case 413: "Payload Too Large"
        case 429: "Too Many Requests"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        case 501: "Not Implemented"
        case 503: "Service Unavailable"
        default: "Error"
        }
    }
}
