import Foundation

public enum MediaKind: String, Codable, Sendable, CaseIterable {
    case audio
    case video

    public var displayName: String {
        switch self {
        case .audio: "音频"
        case .video: "视频"
        }
    }

    public var isVideo: Bool { self == .video }
}
