import Foundation

/// Builds deterministic demo folders for the editor and UI tests.
/// Audio files get a unique trailing marker so SHA-256 deduplication does not
/// collapse them into one item; M4A still plays because the marker is after
/// the audio container's data.
public enum DemoFolderFactory {
    private static let demoMarkerName = ".localpod-demo-v2"
    private static let acceptanceMarkerName = ".localpod-acceptance-v1"

    public static func makeIfNeeded(
        at rootURL: URL,
        audioTemplateURL: URL,
        fileCount: Int = 100
    ) throws -> URL {
        let fileManager = FileManager.default
        if isCurrent(
            rootURL,
            marker: demoMarkerName,
            expectedFiles: fileCount,
            fileManager: fileManager
        ) {
            return rootURL
        }
        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let template = try Data(contentsOf: audioTemplateURL)
        for index in 0..<fileCount {
            let directory = directoryURL(
                for: index,
                under: rootURL,
                fileManager: fileManager
            )
            let name = String(format: "Episode %03d.%@", index + 1, audioTemplateURL.pathExtension)
            var data = template
            data.append(Data("\nLocalPodDemo|\(index)|\(UUID().uuidString)\n".utf8))
            try data.write(to: directory.appendingPathComponent(name))
        }
        try Data().write(to: rootURL.appendingPathComponent(demoMarkerName))
        return rootURL
    }

    /// 100 regular files: 97 unique audio, 1 byte-identical duplicate audio,
    /// 2 unsupported files. Used by the M1 acceptance UI test.
    public static func makeAcceptanceFolderIfNeeded(
        at rootURL: URL,
        audioTemplateURL: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        if isCurrent(
            rootURL,
            marker: acceptanceMarkerName,
            expectedFiles: 100,
            fileManager: fileManager
        ) {
            return rootURL
        }
        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let template = try Data(contentsOf: audioTemplateURL)
        var firstAudioData: Data?
        for index in 0..<97 {
            let directory = directoryURL(
                for: index,
                under: rootURL,
                fileManager: fileManager
            )
            let name = String(format: "Episode %03d.%@", index + 1, audioTemplateURL.pathExtension)
            var data = template
            data.append(Data("\nLocalPodAcceptance|\(index)|\(UUID().uuidString)\n".utf8))
            if index == 0 {
                firstAudioData = data
            }
            try data.write(to: directory.appendingPathComponent(name))
        }

        let duplicateDirectory = directoryURL(for: 0, under: rootURL, fileManager: fileManager)
        if let firstAudioData {
            try firstAudioData.write(
                to: duplicateDirectory.appendingPathComponent("Episode 999 copy.\(audioTemplateURL.pathExtension)")
            )
        }

        let seasonOne = rootURL.appendingPathComponent("Season 1", isDirectory: true)
        try Data("unsupported notes".utf8).write(
            to: seasonOne.appendingPathComponent("notes.txt")
        )
        let seasonThree = rootURL
            .appendingPathComponent("Season 3", isDirectory: true)
            .appendingPathComponent("Disc 2", isDirectory: true)
        try fileManager.createDirectory(at: seasonThree, withIntermediateDirectories: true)
        try Data("unsupported image".utf8).write(
            to: seasonThree.appendingPathComponent("cover.jpg")
        )

        try Data().write(to: rootURL.appendingPathComponent(acceptanceMarkerName))
        return rootURL
    }

    private static func directoryURL(
        for index: Int,
        under rootURL: URL,
        fileManager: FileManager
    ) -> URL {
        let season = index / 40 + 1
        let disc = (index % 40) / 10 + 1
        let directory = rootURL
            .appendingPathComponent("Season \(season)", isDirectory: true)
            .appendingPathComponent("Disc \(disc)", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func isCurrent(
        _ rootURL: URL,
        marker: String,
        expectedFiles: Int,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: rootURL.appendingPathComponent(marker).path) else {
            return false
        }
        return existingCandidateCount(at: rootURL, fileManager: fileManager) == expectedFiles
    }

    private static func existingCandidateCount(
        at rootURL: URL,
        fileManager: FileManager
    ) -> Int {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var count = 0
        while let url = enumerator.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                count += 1
            }
        }
        return count
    }
}
