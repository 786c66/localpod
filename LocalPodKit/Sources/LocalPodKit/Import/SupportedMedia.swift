import Foundation
import UniformTypeIdentifiers

public enum SupportedMedia {
    /// The M0 import surface. VLCKit and other third-party decoders are not used.
    public static let contentTypes: [UTType] = [.audio, .movie]

    public static func kind(for url: URL) -> MediaKind? {
        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        return kind(for: contentType)
    }

    public static func kind(for contentType: UTType?) -> MediaKind? {
        guard let contentType else { return nil }
        if contentType.conforms(to: .audio) { return .audio }
        if contentType.conforms(to: .movie) { return .video }
        return nil
    }
}
