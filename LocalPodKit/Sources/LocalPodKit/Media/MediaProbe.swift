import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum MediaProbeError: LocalizedError {
    case notPlayable(URL)
    case noMediaTracks(URL)
    case thumbnailUnavailable

    public var errorDescription: String? {
        switch self {
        case .notPlayable(let url):
            LocalPodLocalization.format("error.probe.notPlayable", url.lastPathComponent)
        case .noMediaTracks(let url):
            LocalPodLocalization.format("error.probe.noTracks", url.lastPathComponent)
        case .thumbnailUnavailable:
            LocalPodLocalization.string("error.probe.thumbnail")
        }
    }
}

public struct ProbedMedia: Sendable {
    public let durationSeconds: Double?
    public let hasVideoTrack: Bool
    public let hasAudioTrack: Bool
    public let title: String?
    public let artworkJPEGData: Data?

    public init(
        durationSeconds: Double?,
        hasVideoTrack: Bool,
        hasAudioTrack: Bool,
        title: String?,
        artworkJPEGData: Data?
    ) {
        self.durationSeconds = durationSeconds
        self.hasVideoTrack = hasVideoTrack
        self.hasAudioTrack = hasAudioTrack
        self.title = title
        self.artworkJPEGData = artworkJPEGData
    }
}

public protocol MediaProbing: Sendable {
    func probe(url: URL, kindHint: MediaKind) async throws -> ProbedMedia
}

public struct AVMediaProbe: MediaProbing {
    public let artworkMaximumSize: CGSize
    public let thumbnailTime: Double

    public init(
        artworkMaximumSize: CGSize = CGSize(width: 512, height: 512),
        thumbnailTime: Double = 1
    ) {
        self.artworkMaximumSize = artworkMaximumSize
        self.thumbnailTime = thumbnailTime
    }

    public func probe(url: URL, kindHint: MediaKind) async throws -> ProbedMedia {
        let asset = AVURLAsset(url: url)

        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            throw MediaProbeError.notPlayable(url)
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !audioTracks.isEmpty || !videoTracks.isEmpty else {
            throw MediaProbeError.noMediaTracks(url)
        }

        let durationTime = try await asset.load(.duration)
        let durationSeconds: Double?
        if durationTime.isNumeric, durationTime.seconds.isFinite, durationTime.seconds > 0 {
            durationSeconds = durationTime.seconds
        } else {
            durationSeconds = nil
        }

        let metadata = try await asset.load(.commonMetadata)
        var title: String?
        var artworkData: Data?
        for item in metadata {
            if item.commonKey == .commonKeyTitle, title == nil {
                title = try? await item.load(.stringValue)
            }
            if item.commonKey == .commonKeyArtwork, artworkData == nil {
                artworkData = try? await item.load(.dataValue)
            }
        }

        var artworkJPEGData: Data?
        if !videoTracks.isEmpty {
            artworkJPEGData = await Self.videoThumbnail(
                asset: asset,
                time: thumbnailTime,
                maximumSize: artworkMaximumSize
            )
        } else if let artworkData {
            artworkJPEGData = Self.reencodeJPEG(artworkData)
        }

        return ProbedMedia(
            durationSeconds: durationSeconds,
            hasVideoTrack: !videoTracks.isEmpty,
            hasAudioTrack: !audioTracks.isEmpty,
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines),
            artworkJPEGData: artworkJPEGData
        )
    }

    private static func videoThumbnail(
        asset: AVAsset,
        time: Double,
        maximumSize: CGSize
    ) async -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        let requested = CMTime(seconds: time, preferredTimescale: 600)
        do {
            let image = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<CGImage, Error>) in
                generator.generateCGImageAsynchronously(for: requested) { image, _, error in
                    if let image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(
                            throwing: error ?? MediaProbeError.thumbnailUnavailable
                        )
                    }
                }
            }
            return jpegData(from: image)
        } catch {
            return nil
        }
    }

    private static func reencodeJPEG(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return jpegData(from: image)
    }

    private static func jpegData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
