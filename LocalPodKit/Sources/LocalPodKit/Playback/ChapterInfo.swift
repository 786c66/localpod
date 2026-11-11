import Foundation

/// One embedded chapter of the playing file. Titles and ranges come straight
/// from the container metadata (QuickTime/Nero chapters read by AVFoundation);
/// the app never writes or edits them.
public struct ChapterInfo: Codable, Sendable, Equatable, Identifiable {
    public let title: String
    /// Chapter start in seconds from the beginning of the file.
    public let start: Double
    /// Chapter length in seconds. `0` when the container omits a duration.
    public let duration: Double

    public init(title: String, start: Double, duration: Double) {
        self.title = title
        self.start = start
        self.duration = duration
    }

    public var id: String {
        "\(start)-\(duration)-\(title)"
    }

    /// Index of the chapter that contains `time`, or nil when the list is
    /// empty, time is negative, or time is past the last chapter's end.
    /// Chapters are expected ordered by start; the linear scan keeps this
    /// cheap for typical (< 100) chapter counts.
    public static func index(at time: Double, in chapters: [ChapterInfo]) -> Int? {
        guard time.isFinite, time >= 0, !chapters.isEmpty else { return nil }
        var current: Int?
        for (index, chapter) in chapters.enumerated() where chapter.start <= time {
            current = index
        }
        guard let current else { return nil }
        // A final chapter with no usable duration owns everything to the end
        // of the file; bounded chapters stay honest about their range.
        let chapter = chapters[current]
        if chapter.duration > 0, time >= chapter.start + chapter.duration {
            return nil
        }
        return current
    }
}
