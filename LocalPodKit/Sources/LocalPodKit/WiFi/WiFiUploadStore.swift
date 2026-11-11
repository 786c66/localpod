import Foundation

// MARK: - Limits

public struct WiFiUploadLimits: Sendable {
    public let maxFiles: Int
    public let maxFileBytes: Int64
    public let maxTotalBytes: Int64
    public let maxPathDepth: Int
    public let maxPathComponentBytes: Int
    public let maxPathBytes: Int

    public init(
        maxFiles: Int = 20_000,
        maxFileBytes: Int64 = 8 * 1024 * 1024 * 1024,
        maxTotalBytes: Int64 = 32 * 1024 * 1024 * 1024,
        maxPathDepth: Int = 16,
        maxPathComponentBytes: Int = 200,
        maxPathBytes: Int = 1_024
    ) {
        self.maxFiles = max(1, maxFiles)
        self.maxFileBytes = max(1, maxFileBytes)
        self.maxTotalBytes = max(1, maxTotalBytes)
        self.maxPathDepth = max(1, maxPathDepth)
        self.maxPathComponentBytes = max(1, maxPathComponentBytes)
        // A valid path can never be smaller than one component.
        self.maxPathBytes = max(max(1, maxPathBytes), max(1, maxPathComponentBytes))
    }
}

// MARK: - Models

public struct WiFiUploadSession: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let directoryURL: URL

    public init(id: UUID, directoryURL: URL) {
        self.id = id
        self.directoryURL = directoryURL
    }
}

public struct WiFiCompletedUpload: Sendable, Equatable {
    public let sessionID: UUID
    public let directoryURL: URL
    public let suggestedCollectionName: String?

    public init(sessionID: UUID, directoryURL: URL, suggestedCollectionName: String?) {
        self.sessionID = sessionID
        self.directoryURL = directoryURL
        self.suggestedCollectionName = suggestedCollectionName
    }
}

// MARK: - Errors

public enum WiFiUploadError: LocalizedError, Equatable, Sendable {
    case invalidPath
    case tooManyFiles
    case fileTooLarge
    case totalTooLarge
    case sessionNotFound
    case sessionNotComplete
    case sessionAlreadyCompleted
    case byteCountMismatch
    case invalidByteCount
    case cannotCreateDirectory
    case writeFailed
    case sinkClosed
    case serverUnavailable
    case unauthorized
    case rateLimited
    case forbiddenNetwork
    case requestTimeout

    public var errorDescription: String? {
        switch self {
        case .invalidPath:
            LocalPodLocalization.string("error.wifi.invalidPath")
        case .tooManyFiles:
            LocalPodLocalization.string("error.wifi.tooManyFiles")
        case .fileTooLarge:
            LocalPodLocalization.string("error.wifi.fileTooLarge")
        case .totalTooLarge:
            LocalPodLocalization.string("error.wifi.totalTooLarge")
        case .sessionNotFound:
            LocalPodLocalization.string("error.wifi.sessionMissing")
        case .sessionNotComplete:
            LocalPodLocalization.string("error.wifi.sessionNotComplete")
        case .sessionAlreadyCompleted:
            LocalPodLocalization.string("error.wifi.sessionAlreadyCompleted")
        case .byteCountMismatch:
            LocalPodLocalization.string("error.wifi.byteCountMismatch")
        case .invalidByteCount:
            LocalPodLocalization.string("error.wifi.invalidByteCount")
        case .cannotCreateDirectory:
            LocalPodLocalization.string("error.wifi.cannotCreateDirectory")
        case .writeFailed:
            LocalPodLocalization.string("error.wifi.writeFailed")
        case .sinkClosed:
            LocalPodLocalization.string("error.wifi.sinkClosed")
        case .serverUnavailable:
            LocalPodLocalization.string("error.wifi.serverUnavailable")
        case .unauthorized:
            LocalPodLocalization.string("error.wifi.unauthorized")
        case .rateLimited:
            LocalPodLocalization.string("error.wifi.rateLimited")
        case .forbiddenNetwork:
            LocalPodLocalization.string("error.wifi.forbiddenNetwork")
        case .requestTimeout:
            LocalPodLocalization.string("error.wifi.requestTimeout")
        }
    }
}

// MARK: - Store

/// On-disk staging area for files uploaded over Wi-Fi.
///
/// Each session lives in its own directory below `rootURL`. Files keep their
/// relative directory structure so the existing importer can treat the session
/// (or its single top-level folder) as a collection. A hidden completion
/// marker distinguishes sessions ready for import from interrupted ones.
///
/// All mutable state is protected by one lock. Filesystem writes happen while
/// that lock is held for reservation bookkeeping; body streaming happens in
/// `WiFiUploadFileSink` outside the lock.
public final class WiFiUploadStore: @unchecked Sendable {
    public let rootURL: URL
    public let limits: WiFiUploadLimits

    static let completionMarkerName = ".localpod-complete"
    static let partialPrefix = ".partial-"

    private struct SessionRecord {
        let directoryURL: URL
        var committedFileCount = 0
        var committedBytes: Int64 = 0
        var reservedBytes: Int64 = 0
        var reservedSinks: Set<UUID> = []
        var completed = false
        var reservedDestinations: Set<String> = []
    }

    private let lock = NSLock()
    private var sessions: [UUID: SessionRecord] = [:]

    public init(rootURL: URL, limits: WiFiUploadLimits = .init()) {
        self.rootURL = rootURL.standardizedFileURL
        self.limits = limits
    }

    /// Application Support/WiFiUploads, matching the app's other storage.
    public static func liveRootURL() -> URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return support
            .appendingPathComponent("WiFiUploads", isDirectory: true)
            .standardizedFileURL
    }

    public convenience init(limits: WiFiUploadLimits = .init()) throws {
        guard let root = Self.liveRootURL() else {
            throw WiFiUploadError.cannotCreateDirectory
        }
        self.init(rootURL: root, limits: limits)
    }

    // MARK: Session lifecycle

    public func createSession() throws -> WiFiUploadSession {
        try ensureRootDirectory()
        let id = UUID()
        let directory = sessionDirectoryURL(id: id)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw WiFiUploadError.cannotCreateDirectory
        }

        lock.lock()
        sessions[id] = SessionRecord(directoryURL: directory)
        lock.unlock()

        return WiFiUploadSession(id: id, directoryURL: directory)
    }

    public func completeSession(_ sessionID: UUID) throws -> WiFiCompletedUpload {
        lock.lock()
        defer { lock.unlock() }

        guard var record = sessions[sessionID] else {
            throw WiFiUploadError.sessionNotFound
        }
        if record.completed {
            return try Self.completedUpload(
                sessionID: sessionID,
                directory: record.directoryURL
            )
        }
        guard record.reservedSinks.isEmpty, record.committedFileCount > 0 else {
            throw WiFiUploadError.sessionNotComplete
        }

        let marker = record.directoryURL.appendingPathComponent(
            Self.completionMarkerName,
            isDirectory: false
        )
        do {
            try Data("complete".utf8).write(to: marker, options: .atomic)
        } catch {
            throw WiFiUploadError.writeFailed
        }

        record.completed = true
        sessions[sessionID] = record
        return try Self.completedUpload(
            sessionID: sessionID,
            directory: record.directoryURL
        )
    }

    public func removeSession(_ sessionID: UUID) throws {
        lock.lock()
        let inMemory = sessions.removeValue(forKey: sessionID)?.directoryURL
        lock.unlock()

        var directory = inMemory
        if directory == nil {
            let candidate = sessionDirectoryURL(id: sessionID)
            if FileManager.default.fileExists(atPath: candidate.path) {
                directory = candidate
            }
        }
        guard let directory else {
            throw WiFiUploadError.sessionNotFound
        }

        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw WiFiUploadError.writeFailed
        }
    }

    /// Removes every session directory without a completion marker. Completed
    /// sessions are kept for relaunch recovery.
    public func cleanupIncompleteSessions() throws {
        try ensureRootDirectory()

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
        } catch {
            throw WiFiUploadError.writeFailed
        }

        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            let marker = entry.appendingPathComponent(Self.completionMarkerName)
            guard !FileManager.default.fileExists(atPath: marker.path) else { continue }
            do {
                try FileManager.default.removeItem(at: entry)
            } catch {
                throw WiFiUploadError.writeFailed
            }
        }

        lock.lock()
        sessions = sessions.filter { _, record in
            record.completed && FileManager.default.fileExists(
                atPath: record.directoryURL
                    .appendingPathComponent(Self.completionMarkerName)
                    .path
            )
        }
        lock.unlock()
    }

    /// Completed sessions that have not been removed/consumed yet. This also
    /// re-registers them in memory so a restarted app can call
    /// `removeSession(_:)` without reloading the store first.
    public func pendingCompletedSessions() throws -> [WiFiCompletedUpload] {
        try ensureRootDirectory()

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
        } catch {
            throw WiFiUploadError.writeFailed
        }

        let sorted = entries.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
        var results: [WiFiCompletedUpload] = []

        for entry in sorted {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            guard let id = UUID(uuidString: entry.lastPathComponent) else { continue }
            let marker = entry.appendingPathComponent(Self.completionMarkerName)
            guard FileManager.default.fileExists(atPath: marker.path) else { continue }

            let completed = try Self.completedUpload(
                sessionID: id,
                directory: entry.standardizedFileURL
            )
            results.append(completed)

            lock.lock()
            if sessions[id] == nil {
                sessions[id] = SessionRecord(
                    directoryURL: entry.standardizedFileURL,
                    completed: true
                )
            }
            lock.unlock()
        }

        return results
    }

    public func currentSession(id: UUID) -> WiFiUploadSession? {
        lock.lock()
        defer { lock.unlock() }
        guard let record = sessions[id] else { return nil }
        return WiFiUploadSession(id: id, directoryURL: record.directoryURL)
    }

    public func sessionURL(id: UUID) -> URL? {
        lock.lock()
        let directory = sessions[id]?.directoryURL
        lock.unlock()
        if let directory { return directory }

        let candidate = sessionDirectoryURL(id: id)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    // MARK: Uploads

    public func beginFile(
        sessionID: UUID,
        relativePath: String,
        expectedBytes: Int64
    ) throws -> WiFiUploadFileSink {
        let normalizedPath = try Self.validateRelativePath(
            relativePath,
            limits: limits
        )

        guard expectedBytes >= 0 else {
            throw WiFiUploadError.invalidByteCount
        }
        guard expectedBytes <= limits.maxFileBytes else {
            throw WiFiUploadError.fileTooLarge
        }

        try ensureRootDirectory()

        lock.lock()
        defer { lock.unlock() }

        guard var record = sessions[sessionID] else {
            throw WiFiUploadError.sessionNotFound
        }
        guard !record.completed else {
            throw WiFiUploadError.sessionAlreadyCompleted
        }
        guard record.committedFileCount + record.reservedSinks.count < limits.maxFiles else {
            throw WiFiUploadError.tooManyFiles
        }
        let reservedTotal = record.committedBytes + record.reservedBytes
        guard reservedTotal <= limits.maxTotalBytes,
              expectedBytes <= limits.maxTotalBytes - reservedTotal else {
            throw WiFiUploadError.totalTooLarge
        }

        let components = normalizedPath.split(separator: "/").map(String.init)
        guard let fileName = components.last else {
            throw WiFiUploadError.invalidPath
        }
        let destinationDirectory = components
            .dropLast()
            .reduce(record.directoryURL) { url, component in
                url.appendingPathComponent(component, isDirectory: true)
            }
            .standardizedFileURL

        let sessionPath = record.directoryURL.standardizedFileURL.path
        guard destinationDirectory.path == sessionPath
                || destinationDirectory.path.hasPrefix(sessionPath + "/") else {
            throw WiFiUploadError.invalidPath
        }

        do {
            try FileManager.default.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw WiFiUploadError.cannotCreateDirectory
        }

        let destination = try Self.uniqueDestination(
            proposedName: fileName,
            in: destinationDirectory,
            reserved: record.reservedDestinations,
            maxComponentBytes: limits.maxPathComponentBytes
        )
        guard destination.path.hasPrefix(sessionPath + "/") else {
            throw WiFiUploadError.invalidPath
        }

        let sinkID = UUID()
        let partialURL = destinationDirectory.appendingPathComponent(
            Self.partialPrefix + sinkID.uuidString.lowercased(),
            isDirectory: false
        )

        guard FileManager.default.createFile(atPath: partialURL.path, contents: nil) else {
            throw WiFiUploadError.writeFailed
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: partialURL)
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            throw WiFiUploadError.writeFailed
        }

        record.reservedSinks.insert(sinkID)
        record.reservedBytes += expectedBytes
        record.reservedDestinations.insert(destination.standardizedFileURL.path)
        sessions[sessionID] = record

        return WiFiUploadFileSink(
            store: self,
            sessionID: sessionID,
            sinkID: sinkID,
            expectedBytes: expectedBytes,
            partialURL: partialURL,
            proposedDestination: destination,
            handle: handle
        )
    }

    // MARK: Sink support (internal)

    func finalizeSink(
        sessionID: UUID,
        sinkID: UUID,
        proposedDestination: URL,
        partialURL: URL,
        expectedBytes: Int64,
        writtenBytes: Int64
    ) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        guard var record = sessions[sessionID] else {
            throw WiFiUploadError.sessionNotFound
        }
        guard record.reservedSinks.contains(sinkID) else {
            throw WiFiUploadError.sinkClosed
        }

        let proposedPath = proposedDestination.standardizedFileURL.path
        var reserved = record.reservedDestinations
        reserved.remove(proposedPath)

        let finalURL = try Self.uniqueDestination(
            proposedName: proposedDestination.lastPathComponent,
            in: proposedDestination.deletingLastPathComponent(),
            reserved: reserved,
            maxComponentBytes: limits.maxPathComponentBytes
        )

        do {
            try FileManager.default.moveItem(at: partialURL, to: finalURL)
        } catch {
            throw WiFiUploadError.writeFailed
        }

        record.reservedSinks.remove(sinkID)
        record.reservedBytes = max(0, record.reservedBytes - expectedBytes)
        record.committedFileCount += 1
        record.committedBytes += writtenBytes
        record.reservedDestinations.remove(proposedPath)
        record.reservedDestinations.insert(finalURL.standardizedFileURL.path)
        sessions[sessionID] = record

        return finalURL
    }

    func releaseReservation(
        sessionID: UUID,
        sinkID: UUID,
        destination: URL,
        expectedBytes: Int64
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard var record = sessions[sessionID] else { return }
        guard record.reservedSinks.remove(sinkID) != nil else { return }
        record.reservedBytes = max(0, record.reservedBytes - expectedBytes)
        record.reservedDestinations.remove(destination.standardizedFileURL.path)
        sessions[sessionID] = record
    }

    // MARK: Server stop support (internal)

    func removePartialArtifacts(sessionID: UUID) throws {
        guard let directory = sessionURL(id: sessionID) else { return }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return
        }

        while let url = enumerator.nextObject() as? URL {
            guard url.lastPathComponent.hasPrefix(Self.partialPrefix) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw WiFiUploadError.writeFailed
            }
        }
    }

    func containsUploadedFiles(sessionID: UUID) -> Bool {
        guard let directory = sessionURL(id: sessionID) else { return false }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return false
        }

        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            guard name != Self.completionMarkerName,
                  !name.hasPrefix(Self.partialPrefix) else { continue }
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                return true
            }
        }
        return false
    }

    // MARK: Path and name helpers

    /// Strictly validates a percent-decoded UTF-8 relative path. Nothing is
    /// created before this succeeds.
    static func validateRelativePath(
        _ path: String,
        limits: WiFiUploadLimits
    ) throws -> String {
        guard !path.isEmpty else { throw WiFiUploadError.invalidPath }
        guard !path.hasPrefix("/") else { throw WiFiUploadError.invalidPath }
        guard !path.contains("\\") else { throw WiFiUploadError.invalidPath }
        guard path.utf8.count <= limits.maxPathBytes else {
            throw WiFiUploadError.invalidPath
        }
        guard path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw WiFiUploadError.invalidPath
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.count <= limits.maxPathDepth else {
            throw WiFiUploadError.invalidPath
        }

        for componentSlice in components {
            let component = String(componentSlice)
            guard !component.isEmpty else { throw WiFiUploadError.invalidPath }
            guard component != ".", component != ".." else {
                throw WiFiUploadError.invalidPath
            }
            guard !component.hasPrefix(".") else { throw WiFiUploadError.invalidPath }
            guard !component.contains(":") else { throw WiFiUploadError.invalidPath }
            guard component.utf8.count <= limits.maxPathComponentBytes else {
                throw WiFiUploadError.invalidPath
            }
        }

        return components.map(String.init).joined(separator: "/")
    }

    private static func uniqueDestination(
        proposedName: String,
        in directory: URL,
        reserved: Set<String>,
        maxComponentBytes: Int
    ) throws -> URL {
        let original = URL(fileURLWithPath: proposedName)
        let pathExtension = original.pathExtension
        let base = original.deletingPathExtension().lastPathComponent

        var candidate = proposedName
        for index in 2...1_000_000 {
            let url = directory
                .appendingPathComponent(candidate, isDirectory: false)
                .standardizedFileURL
            if !reserved.contains(url.path),
               !FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            candidate = suffixedName(
                base: base,
                pathExtension: pathExtension,
                index: index,
                maxBytes: maxComponentBytes
            )
        }
        throw WiFiUploadError.writeFailed
    }

    private static func suffixedName(
        base: String,
        pathExtension: String,
        index: Int,
        maxBytes: Int
    ) -> String {
        let suffix = pathExtension.isEmpty ? "-\(index)" : "-\(index).\(pathExtension)"
        var trimmedBase = base
        while !trimmedBase.isEmpty,
              trimmedBase.utf8.count + suffix.utf8.count > maxBytes {
            trimmedBase.removeLast()
        }

        var value = trimmedBase + suffix
        while value.utf8.count > maxBytes, !value.isEmpty {
            value.removeFirst()
        }
        return value.isEmpty ? String(index) : value
    }

    private static func completedUpload(
        sessionID: UUID,
        directory: URL
    ) throws -> WiFiCompletedUpload {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
        } catch {
            throw WiFiUploadError.sessionNotFound
        }

        let visible = entries.filter { !$0.lastPathComponent.hasPrefix(".") }
        if visible.count == 1, let only = visible.first {
            let values = try? only.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            if values?.isDirectory == true, values?.isSymbolicLink != true {
                return WiFiCompletedUpload(
                    sessionID: sessionID,
                    directoryURL: only.standardizedFileURL,
                    suggestedCollectionName: only.lastPathComponent
                )
            }
        }

        return WiFiCompletedUpload(
            sessionID: sessionID,
            directoryURL: directory.standardizedFileURL,
            suggestedCollectionName: nil
        )
    }

    private func ensureRootDirectory() throws {
        do {
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw WiFiUploadError.cannotCreateDirectory
        }
    }

    private func sessionDirectoryURL(id: UUID) -> URL {
        rootURL
            .appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
            .standardizedFileURL
    }
}

// MARK: - Sink

/// A single in-flight file upload. Data is streamed through a `FileHandle`;
/// the final path only appears after `finish()` verifies the byte count and
/// atomically moves the hidden partial file.
public final class WiFiUploadFileSink: @unchecked Sendable {
    public let expectedBytes: Int64

    private enum State {
        case open
        case finishing
        case finished(URL)
        case failed
        case cancelled
    }

    private let store: WiFiUploadStore
    private let sessionID: UUID
    private let sinkID: UUID
    private let partialURL: URL
    private let proposedDestination: URL

    private let lock = NSLock()
    private var state: State = .open
    private var handle: FileHandle?
    private var writtenBytes: Int64 = 0

    init(
        store: WiFiUploadStore,
        sessionID: UUID,
        sinkID: UUID,
        expectedBytes: Int64,
        partialURL: URL,
        proposedDestination: URL,
        handle: FileHandle
    ) {
        self.store = store
        self.sessionID = sessionID
        self.sinkID = sinkID
        self.expectedBytes = expectedBytes
        self.partialURL = partialURL
        self.proposedDestination = proposedDestination
        self.handle = handle
    }

    deinit {
        cancel()
    }

    public func append(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        guard case .open = state, let handle else {
            throw WiFiUploadError.sinkClosed
        }
        guard Int64(data.count) <= expectedBytes - writtenBytes else {
            throw WiFiUploadError.fileTooLarge
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw WiFiUploadError.writeFailed
        }
        writtenBytes += Int64(data.count)
    }

    public func finish() throws -> URL {
        lock.lock()
        switch state {
        case .finished(let url):
            lock.unlock()
            return url
        case .finishing, .failed, .cancelled:
            lock.unlock()
            throw WiFiUploadError.sinkClosed
        case .open:
            state = .finishing
            let openHandle = handle
            handle = nil
            let written = writtenBytes
            lock.unlock()

            guard let openHandle else {
                discardReservation()
                fail()
                throw WiFiUploadError.writeFailed
            }

            do {
                try openHandle.synchronize()
                try openHandle.close()
            } catch {
                try? openHandle.close()
                discardReservation()
                fail()
                throw WiFiUploadError.writeFailed
            }

            let actualBytes: Int64
            do {
                let attributes = try FileManager.default.attributesOfItem(
                    atPath: partialURL.path
                )
                actualBytes = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            } catch {
                discardReservation()
                fail()
                throw WiFiUploadError.writeFailed
            }

            guard actualBytes == expectedBytes, written == expectedBytes else {
                discardReservation()
                fail()
                throw WiFiUploadError.byteCountMismatch
            }

            do {
                let finalURL = try store.finalizeSink(
                    sessionID: sessionID,
                    sinkID: sinkID,
                    proposedDestination: proposedDestination,
                    partialURL: partialURL,
                    expectedBytes: expectedBytes,
                    writtenBytes: written
                )
                lock.lock()
                state = .finished(finalURL)
                lock.unlock()
                return finalURL
            } catch let error as WiFiUploadError {
                try? FileManager.default.removeItem(at: partialURL)
                store.releaseReservation(
                    sessionID: sessionID,
                    sinkID: sinkID,
                    destination: proposedDestination,
                    expectedBytes: expectedBytes
                )
                fail()
                throw error
            } catch {
                try? FileManager.default.removeItem(at: partialURL)
                store.releaseReservation(
                    sessionID: sessionID,
                    sinkID: sinkID,
                    destination: proposedDestination,
                    expectedBytes: expectedBytes
                )
                fail()
                throw WiFiUploadError.writeFailed
            }
        }
    }

    public func cancel() {
        lock.lock()
        guard case .open = state else {
            lock.unlock()
            return
        }
        state = .cancelled
        let openHandle = handle
        handle = nil
        lock.unlock()

        try? openHandle?.close()
        try? FileManager.default.removeItem(at: partialURL)
        store.releaseReservation(
            sessionID: sessionID,
            sinkID: sinkID,
            destination: proposedDestination,
            expectedBytes: expectedBytes
        )
    }

    private func fail() {
        lock.lock()
        if case .finishing = state {
            state = .failed
        }
        lock.unlock()
    }

    private func discardReservation() {
        try? FileManager.default.removeItem(at: partialURL)
        store.releaseReservation(
            sessionID: sessionID,
            sinkID: sinkID,
            destination: proposedDestination,
            expectedBytes: expectedBytes
        )
    }
}
