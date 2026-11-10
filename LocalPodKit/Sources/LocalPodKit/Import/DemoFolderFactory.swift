import Foundation

/// Builds a deterministic 3-level, 100-file folder for Spike A. The folder is
/// kept out of Documents so file sharing only exposes the real inbox.
public enum DemoFolderFactory {
    public static func makeIfNeeded(
        at rootURL: URL,
        audioTemplateURL: URL,
        fileCount: Int = 100
    ) throws -> URL {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: rootURL.path) {
            if existingMediaCount(at: rootURL, fileManager: fileManager) == fileCount {
                return rootURL
            }
            try fileManager.removeItem(at: rootURL)
        }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        for index in 0..<fileCount {
            let season = index / 40 + 1
            let disc = (index % 40) / 10 + 1
            let directory = rootURL
                .appendingPathComponent("Season \(season)", isDirectory: true)
                .appendingPathComponent("Disc \(disc)", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let name = String(format: "Episode %03d.%@", index + 1, audioTemplateURL.pathExtension)
            try fileManager.copyItem(
                at: audioTemplateURL,
                to: directory.appendingPathComponent(name)
            )
        }
        return rootURL
    }

    private static func existingMediaCount(at rootURL: URL, fileManager: FileManager) -> Int {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var count = 0
        while let url = enumerator.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey])
            if values?.isRegularFile == true, SupportedMedia.kind(for: values?.contentType) != nil {
                count += 1
            }
        }
        return count
    }
}
