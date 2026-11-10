import Foundation
import Observation
@preconcurrency import AVFoundation
@preconcurrency import MediaPlayer
#if os(iOS)
@preconcurrency import UIKit
#endif

/// M0 playback spike: one AVPlayer for audio and video, Now Playing metadata,
/// remote commands, audio session interruption/route handling and a periodic
/// time observer. PiP and full recovery/state machine are M2 work.
@MainActor
@Observable
public final class PlaybackController {
    public private(set) var currentItem: PlaybackItem?
    public private(set) var isPlaying = false
    public private(set) var currentTime: Double = 0
    public private(set) var duration: Double = 0
    public private(set) var errorMessage: String?
    public private(set) var statusText = "未播放"
    public var playbackRate: Float = 1.0 {
        didSet {
            if isPlaying {
                player.rate = playbackRate
            }
            updateNowPlaying()
        }
    }

    @ObservationIgnored public let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var routeChangeObserver: NSObjectProtocol?
    @ObservationIgnored private var wasPlayingBeforeInterruption = false
    @ObservationIgnored private var shouldAutoplay = false
    @ObservationIgnored private var artworkCache: [UUID: MPMediaItemArtwork] = [:]

    public var isVideo: Bool { currentItem?.kind == .video }

    public init() {
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = true
        addPeriodicTimeObserver()
        addTimeControlObserver()
        configureRemoteCommands()
        registerAudioSessionObservers()
    }

    public func load(_ item: PlaybackItem, autoplay: Bool = true) {
        currentItem = item
        currentTime = 0
        duration = item.durationHint ?? 0
        errorMessage = nil
        statusText = "加载中"
        shouldAutoplay = autoplay

        statusObservation?.invalidate()
        let playerItem = AVPlayerItem(url: item.fileURL)
        player.replaceCurrentItem(with: playerItem)
        statusObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            let status = observed.status
            let itemDuration = observed.duration.seconds
            let error = observed.error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handleStatus(status, duration: itemDuration, error: error)
            }
        }

        Task { [weak self] in
            let asset = AVURLAsset(url: item.fileURL)
            guard let loaded = try? await asset.load(.duration) else { return }
            let seconds = loaded.seconds
            if seconds.isFinite, seconds > 0 {
                self?.duration = seconds
                self?.updateNowPlaying()
            }
        }
    }

    public func play() {
        guard currentItem != nil else { return }
        #if os(iOS)
        activateAudioSession()
        #endif
        player.play()
        player.rate = playbackRate
        isPlaying = true
        statusText = "播放中"
        updateNowPlaying()
    }

    public func pause() {
        player.pause()
        isPlaying = false
        statusText = "已暂停"
        updateNowPlaying()
    }

    public func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    public func seek(to seconds: Double) {
        guard currentItem != nil else { return }
        let upperBound = duration > 0 ? duration : max(seconds, 0)
        let target = min(max(seconds, 0), upperBound)
        currentTime = target
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        updateNowPlaying()
    }

    public func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    public func setRate(_ rate: Float) {
        playbackRate = min(max(rate, 0.5), 3.0)
    }

    private func handleStatus(
        _ status: AVPlayerItem.Status,
        duration itemDuration: Double,
        error: String?
    ) {
        switch status {
        case .readyToPlay:
            if duration <= 0, itemDuration.isFinite, itemDuration > 0 {
                duration = itemDuration
            }
            statusText = "就绪"
            if shouldAutoplay {
                shouldAutoplay = false
                play()
            }
        case .failed:
            errorMessage = error ?? "播放失败"
            statusText = "失败"
            isPlaying = false
        case .unknown:
            break
        @unknown default:
            break
        }
        updateNowPlaying()
    }

    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                guard let self, seconds.isFinite else { return }
                self.currentTime = seconds
                if self.duration <= 0, let itemDuration = self.player.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                self.updateNowPlaying()
            }
        }
    }

    private func addTimeControlObserver() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observed, _ in
            let status = observed.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                if status == .playing {
                    self.isPlaying = true
                } else if status == .paused, self.isPlaying {
                    self.isPlaying = false
                }
                self.updateNowPlaying()
            }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [15]
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.togglePlayPause() }
            return .success
        }
        center.skipForwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor [weak self] in self?.skip(by: interval) }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor [weak self] in self?.skip(by: -interval) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = positionEvent.positionTime
            Task { @MainActor [weak self] in self?.seek(to: position) }
            return .success
        }
    }

    private func registerAudioSessionObservers() {
        #if os(iOS)
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
            }
        }

        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleRouteChange(reasonRaw: reasonRaw)
            }
        }
        #endif
    }

    #if os(iOS)
    private func activateAudioSession() {
        let video = isVideo
        // AVAudioSession activation can block; keep it off the main thread so
        // the play button and remote commands stay responsive.
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let session = AVAudioSession.sharedInstance()
                let mode: AVAudioSession.Mode = video ? .moviePlayback : .spokenAudio
                try session.setCategory(.playback, mode: mode, options: [.allowAirPlay])
                try session.setActive(true)
            } catch {
                let message = "音频会话激活失败：\(error.localizedDescription)"
                await MainActor.run { [weak self] in
                    self?.errorMessage = message
                }
            }
        }
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else {
            return
        }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying { pause() }
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            if options.contains(.shouldResume), wasPlayingBeforeInterruption {
                play()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonRaw: UInt?) {
        guard let reasonRaw,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else {
            return
        }
        if reason == .oldDeviceUnavailable {
            pause()
        }
    }
    #endif

    private func updateNowPlaying() {
        guard let item = currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.subtitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0,
            MPNowPlayingInfoPropertyMediaType: item.kind.isVideo
                ? MPNowPlayingInfoMediaType.video.rawValue
                : MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let artwork = artwork(for: item) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    #if os(iOS)
    private func artwork(for item: PlaybackItem) -> MPMediaItemArtwork? {
        if let cached = artworkCache[item.id] {
            return cached
        }
        let artwork = Self.makeArtwork(item: item)
        artworkCache[item.id] = artwork
        return artwork
    }

    /// The artwork request handler is invoked by MediaPlayer on a background
    /// queue. Keep it out of the main-actor-isolated method so the generated
    /// closure does not inherit MainActor isolation (which traps at runtime).
    nonisolated private static func makeArtwork(item: PlaybackItem) -> MPMediaItemArtwork {
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let colors = [
                UIColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 1).cgColor,
                UIColor(red: 0.11, green: 0.65, blue: 0.62, alpha: 1).cgColor
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            let symbolName = item.kind.isVideo ? "play.rectangle.fill" : "waveform.circle.fill"
            if let symbol = UIImage(systemName: symbolName)?.withTintColor(
                .white,
                renderingMode: .alwaysOriginal
            ) {
                symbol.draw(in: CGRect(x: 180, y: 180, width: 240, height: 240))
            }
        }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
    #else
    private func artwork(for item: PlaybackItem) -> MPMediaItemArtwork? {
        nil
    }
    #endif
}
