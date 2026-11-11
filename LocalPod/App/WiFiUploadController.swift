import Foundation
import Observation
import LocalPodKit

/// Owns the lifetime of the foreground-only LAN upload server. The server is
/// deliberately not an app-wide singleton: opening Wi-Fi Upload starts it,
/// and leaving the screen or backgrounding the app stops it.
@MainActor
@Observable
final class WiFiUploadController {
    enum Phase: Equatable {
        case idle
        case starting
        case running
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var info: WiFiUploadServerInfo?
    private(set) var pin = ""
    private(set) var uploadedFileCount = 0
    private(set) var lastUploadedFileName: String?
    private(set) var lastCompletedSessionID: UUID?
    private(set) var lastError: String?
    private(set) var isDemo = false
    private(set) var isStopping = false

    @ObservationIgnored private var server: WiFiUploadServer?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    /// Called on the main actor whenever the browser finishes a batch. The
    /// completed directory is retained until the import finishes (or until
    /// launch recovery consumes it).
    @ObservationIgnored var onSessionCompleted: ((WiFiCompletedUpload) -> Void)?

    /// Shared store so ImportCoordinator recovery sees the same completed
    /// sessions the server wrote.
    static let store = WiFiUploadStorage.store

    static let limits = WiFiUploadLimits()

    var primaryURL: URL? {
        info?.urls.first
    }

    var isRunning: Bool {
        phase == .running
    }

    func start() async {
        guard phase != .starting, phase != .running else { return }
        generation += 1
        let generation = generation
        isStopping = false
        uploadedFileCount = 0
        lastUploadedFileName = nil
        lastCompletedSessionID = nil
        lastError = nil
        info = nil
        isDemo = false
        phase = .starting

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--p1-wifi-demo") {
            // Deterministic UI seam. Real server behavior is covered by
            // LocalPodKit loopback tests; this only avoids prompting for local
            // network permission in simulator UI tests.
            try? await Task.sleep(for: .milliseconds(250))
            guard generation == self.generation else { return }
            isDemo = true
            pin = "246810"
            info = WiFiUploadServerInfo(
                port: 8080,
                urls: [URL(string: "http://192.0.2.10:8080")].compactMap { $0 }
            )
            phase = .running
            return
        }
        #endif

        let pin = WiFiPIN.generate()
        self.pin = pin
        let server = WiFiUploadServer(store: Self.store, pin: pin)
        self.server = server

        let events = server.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.handle(event)
            }
        }

        do {
            let info = try await server.start()
            guard generation == self.generation else {
                await server.stop()
                return
            }
            self.info = info
            phase = .running
        } catch {
            await server.stop()
            eventTask?.cancel()
            eventTask = nil
            self.server = nil
            guard generation == self.generation else { return }
            phase = .failed
            lastError = error.localizedDescription
        }
    }

    func stop() async {
        guard phase != .idle || server != nil else { return }
        generation += 1
        isStopping = true
        eventTask?.cancel()
        eventTask = nil
        if let server {
            await server.stop()
        }
        server = nil
        phase = .idle
        info = nil
        pin = ""
        uploadedFileCount = 0
        lastUploadedFileName = nil
        lastCompletedSessionID = nil
        isDemo = false
        isStopping = false
    }

    private func handle(_ event: WiFiUploadServerEvent) {
        switch event {
        case .ready(let info):
            self.info = info
        case .uploadFinished(let fileName, _):
            uploadedFileCount += 1
            lastUploadedFileName = fileName
        case .sessionCompleted(let completed):
            lastCompletedSessionID = completed.sessionID
            onSessionCompleted?(completed)
        case .failed(let message):
            lastError = message
        }
    }
}
