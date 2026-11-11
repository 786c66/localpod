import Foundation
import LocalPodKit

/// Shared staging store for browser uploads. The upload server writes into it
/// and ImportCoordinator consumes completed sessions, so both must use the
/// same Application Support directory.
enum WiFiUploadStorage {
    static let store: WiFiUploadStore = {
        let fileManager = FileManager.default
        let root = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ))?.appendingPathComponent("WiFiUploads", isDirectory: true)
            ?? fileManager.temporaryDirectory
                .appendingPathComponent("WiFiUploads", isDirectory: true)
        return WiFiUploadStore(rootURL: root)
    }()
}
