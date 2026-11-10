#if DEBUG
import Foundation
import LocalPodKit

/// Debug-only fixtures used by M4 UI tests and manual simulator validation.
/// Nothing here is compiled into Release builds.
enum M4DebugSupport {
    /// Copies the bundled demo audio to a temporary URL *outside*
    /// `Documents/Import`, so `handleOpenURL` exercises the real open-in path.
    static func makeOpenInSourceURL() -> URL? {
        guard let source = Bundle.main.url(forResource: "demo-audio", withExtension: "m4a") else {
            return nil
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("m4-open-in-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let destination = directory.appendingPathComponent("demo-audio.m4a")
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    static func removeOpenInSource(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func seedUnsupportedInbox() {
        guard let inbox = try? ImportInbox.live.ensureExists() else { return }
        let destination = inbox.appendingPathComponent("NotMedia.txt")
        try? FileManager.default.removeItem(at: destination)
        try? Data("LocalPod only imports audio and movie files.\n".utf8)
            .write(to: destination, options: .atomic)
    }

    /// Writes the bundled demo audio into `Documents/Import/SlowDrop.m4a` in
    /// 32 chunks over roughly 5.6 seconds. The foreground watcher must not
    /// import anything until the write finishes and the metadata is quiet.
    static func startSlowInboxWriter() {
        guard let source = Bundle.main.url(forResource: "demo-audio", withExtension: "m4a"),
              let inbox = try? ImportInbox.live.ensureExists() else {
            return
        }
        let destination = inbox.appendingPathComponent("SlowDrop.m4a")
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destination)
        guard fileManager.createFile(atPath: destination.path, contents: nil) else { return }

        Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: source),
                  let handle = try? FileHandle(forWritingTo: destination) else {
                return
            }
            defer { try? handle.close() }

            let chunkCount = 32
            let chunkSize = max(1, data.count / chunkCount)
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                try? handle.write(contentsOf: data[offset..<end])
                offset = end
                try? await Task.sleep(for: .milliseconds(175))
            }
        }
    }
}
#endif
