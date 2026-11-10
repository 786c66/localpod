import Foundation

public enum MediaKind: String, Codable, Sendable, CaseIterable {
    case audio
    case video

    public var displayName: String {
        displayName(locale: nil)
    }

    public func displayName(locale: Locale?) -> String {
        switch self {
        case .audio: LocalPodLocalization.string("kind.audio", locale: locale)
        case .video: LocalPodLocalization.string("kind.video", locale: locale)
        }
    }

    public var isVideo: Bool { self == .video }
}
