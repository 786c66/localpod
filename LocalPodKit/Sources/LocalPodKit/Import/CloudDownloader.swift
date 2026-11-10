import Foundation

public enum CloudDownloadError: LocalizedError {
    case notDownloaded(URL)
    case providerUnavailable(URL, String?)
    case timedOut(URL)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notDownloaded(let url):
            LocalPodLocalization.format("error.cloud.notDownloaded", url.lastPathComponent)
        case .providerUnavailable(let url, let message):
            LocalPodLocalization.format(
                "error.cloud.providerUnavailable",
                url.lastPathComponent,
                message ?? LocalPodLocalization.string("error.cloud.providerFallback")
            )
        case .timedOut(let url):
            LocalPodLocalization.format("error.cloud.timedOut", url.lastPathComponent)
        case .cancelled:
            LocalPodLocalization.string("error.cloud.cancelled")
        }
    }
}

public protocol CloudDownloading: Sendable {
    func ensureDownloaded(
        at url: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws
}

public struct ICloudDownloader: CloudDownloading {
    public let pollInterval: Duration
    public let timeout: Duration

    public init(
        pollInterval: Duration = .milliseconds(500),
        timeout: Duration = .seconds(600)
    ) {
        self.pollInterval = pollInterval
        self.timeout = timeout
    }

    public func ensureDownloaded(
        at url: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemDownloadingErrorKey
        ]
        var values = try url.resourceValues(forKeys: keys)
        guard values.isUbiquitousItem == true,
              values.ubiquitousItemDownloadingStatus != .current else {
            progress(1)
            return
        }

        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            throw CloudDownloadError.providerUnavailable(
                url,
                error.localizedDescription
            )
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            values = try url.resourceValues(forKeys: keys)
            if values.ubiquitousItemDownloadingStatus == .current {
                progress(1)
                return
            }
            if let downloadError = values.ubiquitousItemDownloadingError {
                throw CloudDownloadError.providerUnavailable(
                    url,
                    downloadError.localizedDescription
                )
            }
            progress(nil)
            try await Task.sleep(for: pollInterval)
        }
        throw CloudDownloadError.timedOut(url)
    }
}
