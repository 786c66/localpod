import Foundation
import Observation
@preconcurrency import AVFoundation
@preconcurrency import MediaPlayer
#if os(iOS)
@preconcurrency import UIKit
#endif

public enum PlaybackPhase: String, Sendable, Equatable {
    case idle
    case preparing
    case ready
    case playing
    case paused
    case buffering
    case interrupted
    case ended
    case failed

    public var statusText: String {
        statusText(locale: nil)
    }

    public func statusText(locale: Locale?) -> String {
        switch self {
        case .idle: LocalPodLocalization.string("playback.phase.idle", locale: locale)
        case .preparing: LocalPodLocalization.string("playback.phase.preparing", locale: locale)
        case .ready: LocalPodLocalization.string("playback.phase.ready", locale: locale)
        case .playing: LocalPodLocalization.string("playback.phase.playing", locale: locale)
        case .paused: LocalPodLocalization.string("playback.phase.paused", locale: locale)
        case .buffering: LocalPodLocalization.string("playback.phase.buffering", locale: locale)
        case .interrupted: LocalPodLocalization.string("playback.phase.interrupted", locale: locale)
        case .ended: LocalPodLocalization.string("playback.phase.ended", locale: locale)
        case .failed: LocalPodLocalization.string("playback.phase.failed", locale: locale)
        }
    }
}

/// Single AVPlayer for audio-only playback. Video files are played for their
/// audio track only; the controller never presents a video surface. It owns the
/// playback state machine, audio session, Now Playing/remote commands and
/// progress persistence. UI only observes and sends intents.
@MainActor
@Observable
public final class PlaybackController {
    public private(set) var currentItem: PlaybackItem?
    public private(set) var phase: PlaybackPhase = .idle
    public private(set) var currentTime: Double = 0
    public private(set) var duration: Double = 0
    public private(set) var errorMessage: String?
    public private(set) var playbackRate: Float = 1.0
    public private(set) var skipForwardInterval: Double = 15
    public private(set) var skipBackwardInterval: Double = 15
    /// When false, loaded items ignore saved progress. Progress is still saved.
    public var resumesSavedProgress = true

    /// The queue/session installs these. `onItemEnded` fires after the finished
    /// progress write, so auto-advance never races the final checkpoint.
    @ObservationIgnored public var onItemEnded: (() -> Void)?
    @ObservationIgnored public var onNextTrack: (() -> Void)?
    @ObservationIgnored public var onPreviousTrack: (() -> Void)?

    @ObservationIgnored public let player = AVPlayer()
    @ObservationIgnored private var progressStore: PlaybackProgressStore?

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var failedToEndObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var routeChangeObserver: NSObjectProtocol?
    @ObservationIgnored private var mediaServicesResetObserver: NSObjectProtocol?

    @ObservationIgnored private var pendingSeekPosition: Double = 0
    @ObservationIgnored private var pendingAutoplay = false
    @ObservationIgnored private var didRecordPlayStart = false
    @ObservationIgnored private var playIntent = false
    @ObservationIgnored private var wasPlayingBeforeInterruption = false
    @ObservationIgnored private var lastProgressSaveDate = Date.distantPast
    @ObservationIgnored private var lastSavedPosition: Double = 0
    @ObservationIgnored private var cachedArtworkKey: String?
    @ObservationIgnored private var cachedArtwork: MPMediaItemArtwork?

    public var isPlaying: Bool {
        phase == .playing || phase == .buffering
    }

    public var statusText: String {
        phase.statusText
    }

    public init() {
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = true
        addPeriodicTimeObserver()
        addTimeControlObserver()
        configureRemoteCommands()
        registerAudioSessionObservers()
    }

    /// Called by the app once SwiftData is ready. Playback works without a
    /// store (demo media, previews), but library items then do not persist
    /// progress.
    public func attachProgressStore(_ store: PlaybackProgressStore) {
        progressStore = store
    }

    // MARK: - Loading

    public func load(_ item: PlaybackItem, autoplay: Bool = true) {
        persistProgress(force: true)
        teardownItemObservers()

        currentItem = item
        currentTime = 0
        duration = item.durationHint.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0
        errorMessage = nil
        playbackRate = PlaybackPolicy.clampedRate(playbackRate)
        playIntent = false
        didRecordPlayStart = false

        var resumePosition: Double = 0
        if resumesSavedProgress,
           let libraryItemID = item.libraryItemID,
           let progressStore {
            resumePosition = (try? progressStore.resumePosition(
                for: libraryItemID,
                fallbackDuration: item.durationHint
            )) ?? 0
        }
        if resumePosition > 0 {
            currentTime = resumePosition
        }
        lastSavedPosition = currentTime

        installPlayerItem(
            for: item,
            seek: resumePosition,
            autoplay: autoplay
        )
        updateNowPlaying()
    }

    public func play() {
        guard let item = currentItem else { return }
        if phase == .failed {
            // A tap on play after a decode/server error retries and resumes.
            errorMessage = nil
            installPlayerItem(for: item, seek: currentTime, autoplay: true)
            return
        }
        if phase == .preparing {
            pendingAutoplay = true
            activateAudioSession()
            return
        }

        if phase == .ended {
            seek(to: 0, persistImmediately: false)
            pendingSeekPosition = 0
            didRecordPlayStart = false
        }

        activateAudioSession()
        recordPlayStartIfNeeded(item: item)
        playIntent = true
        player.play()
        player.rate = playbackRate
        phase = .playing
        updateNowPlaying()
    }

    public func pause() {
        pause(userInitiated: true)
    }

    public func togglePlayPause() {
        if isPlaying || (phase == .preparing && pendingAutoplay) {
            pause()
        } else {
            play()
        }
    }

    private func pause(userInitiated: Bool) {
        guard currentItem != nil else { return }
        if phase == .preparing {
            pendingAutoplay = false
            return
        }
        pendingAutoplay = false
        playIntent = false
        player.pause()
        if phase != .interrupted {
            phase = .paused
        }
        persistProgress(force: true)
        updateNowPlaying()
    }

    public func seek(to seconds: Double, persistImmediately: Bool = true) {
        guard currentItem != nil else { return }
        let upperBound = duration > 0 ? duration : max(seconds, 0)
        let target = min(max(seconds, 0), upperBound)
        currentTime = target
        pendingSeekPosition = target
        if phase == .ended, target < upperBound - 0.001 {
            phase = .paused
            playIntent = false
        }
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        if persistImmediately {
            persistProgress(force: true)
        }
        updateNowPlaying()
    }

    public func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    public func setRate(_ rate: Float) {
        playbackRate = PlaybackPolicy.clampedRate(rate)
        if playIntent {
            player.rate = playbackRate
        }
        updateNowPlaying()
    }

    public func setSkipIntervals(forward: Double, backward: Double) {
        skipForwardInterval = min(max(forward, 5), 120)
        skipBackwardInterval = min(max(backward, 5), 120)
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForwardInterval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackwardInterval)]
    }

    /// Clears the current item and returns to idle. Used when the current queue
    /// item is deleted and no replacement remains.
    public func stop() {
        persistProgress(force: true)
        playIntent = false
        pendingAutoplay = false
        player.pause()
        teardownItemObservers()
        player.replaceCurrentItem(with: nil)
        currentItem = nil
        currentTime = 0
        duration = 0
        errorMessage = nil
        phase = .idle
        lastSavedPosition = 0
        updateNowPlaying()
    }

    /// Rebuild the player item after a decode error or media-services reset.
    public func retry() {
        guard let item = currentItem else { return }
        let position = max(currentTime, pendingSeekPosition)
        let autoplay = playIntent
        errorMessage = nil
        installPlayerItem(for: item, seek: position, autoplay: autoplay)
        updateNowPlaying()
    }

    // MARK: - App lifecycle

    /// Audio keeps playing in the background. The app calls this only to force
    /// a progress checkpoint before iOS may suspend the process.
    public func handleSceneDidEnterBackground() {
        persistProgress(force: true)
    }

    // MARK: - Player item lifecycle

    private func installPlayerItem(
        for item: PlaybackItem,
        seek: Double,
        autoplay: Bool
    ) {
        teardownItemObservers()
        phase = .preparing
        errorMessage = nil
        pendingSeekPosition = max(seek, 0)
        pendingAutoplay = autoplay
        playIntent = false
        if pendingSeekPosition > 0 {
            currentTime = pendingSeekPosition
        }

        let playerItem = AVPlayerItem(url: item.fileURL)
        // Pitch correction for every rate; requirement: voice must not change
        // pitch at 0.5x...3.0x.
        playerItem.audioTimePitchAlgorithm = .timeDomain
        let itemID = item.id

        statusObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            let status = observed.status
            let itemDuration = observed.duration.seconds
            let error = observed.error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handleStatus(
                    status,
                    itemID: itemID,
                    itemDuration: itemDuration,
                    error: error
                )
            }
        }

        let center = NotificationCenter.default
        endObserver = center.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePlaybackEnded(itemID: itemID)
            }
        }
        failedToEndObserver = center.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self] note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.currentItem?.id == itemID else { return }
                self.handleFailure(
                    message: message
                        ?? LocalPodLocalization.string("playback.error.interrupted")
                )
            }
        }

        player.replaceCurrentItem(with: playerItem)
        loadAssetDuration(item: item)
    }

    private func loadAssetDuration(item: PlaybackItem) {
        Task { [weak self] in
            let asset = AVURLAsset(url: item.fileURL)
            guard let loaded = try? await asset.load(.duration) else { return }
            let seconds = loaded.seconds
            guard seconds.isFinite, seconds > 0 else { return }
            await MainActor.run { [weak self] in
                guard let self, self.currentItem?.id == item.id else { return }
                if seconds > self.duration || self.duration <= 0 {
                    self.duration = seconds
                }
                self.updateNowPlaying()
            }
        }
    }

    private func handleStatus(
        _ status: AVPlayerItem.Status,
        itemID: UUID,
        itemDuration: Double,
        error: String?
    ) {
        guard currentItem?.id == itemID else { return }
        switch status {
        case .readyToPlay:
            if itemDuration.isFinite, itemDuration > 0 {
                duration = itemDuration
            }
            let seekTarget = pendingSeekPosition
            pendingSeekPosition = 0
            if seekTarget > 0 {
                currentTime = seekTarget
                player.seek(
                    to: CMTime(seconds: seekTarget, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
            }
            if pendingAutoplay {
                pendingAutoplay = false
                phase = .ready
                play()
            } else {
                phase = .ready
                // The item duration is now known; make sure a resume position
                // saved before the first ready state has a real duration.
                if currentTime > 0 {
                    persistProgress(force: true)
                }
            }
        case .failed:
            handleFailure(
                message: error
                    ?? LocalPodLocalization.string("playback.error.failed")
            )
        case .unknown:
            phase = .preparing
        @unknown default:
            phase = .preparing
        }
        updateNowPlaying()
    }

    private func handlePlaybackEnded(itemID: UUID) {
        guard currentItem?.id == itemID else { return }
        playIntent = false
        pendingAutoplay = false
        phase = .ended
        if duration > 0 {
            currentTime = duration
        }
        persistProgress(force: true, finishedOverride: true)
        updateNowPlaying()
        onItemEnded?()
    }

    private func handleFailure(message: String) {
        guard currentItem != nil else { return }
        playIntent = false
        pendingAutoplay = false
        errorMessage = message
        phase = .failed
        player.pause()
        persistProgress(force: true)
        updateNowPlaying()
    }

    private func teardownItemObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }
    }

    // MARK: - Progress persistence

    private func recordPlayStartIfNeeded(item: PlaybackItem) {
        guard !didRecordPlayStart, let libraryItemID = item.libraryItemID else { return }
        guard let progressStore else { return }
        didRecordPlayStart = true
        _ = try? progressStore.recordPlayStart(itemID: libraryItemID, duration: duration)
    }

    private func persistProgress(force: Bool = false, finishedOverride: Bool? = nil) {
        guard let item = currentItem, let libraryItemID = item.libraryItemID else { return }
        guard let progressStore else { return }
        if !force {
            guard phase == .playing || phase == .buffering else { return }
        }
        let wallClockDue = Date().timeIntervalSince(lastProgressSaveDate) >= 1.0
        // At 3x a wall-clock-only throttle could lose up to 3s of media on a
        // force quit; also save when the media position moved by 1s.
        let positionDue = abs(currentTime - lastSavedPosition) >= 1.0
        guard force || wallClockDue || positionDue else { return }
        guard duration > 0 || currentTime > 0 else { return }

        let finished = finishedOverride
            ?? (duration > 0 && PlaybackPolicy.isFinished(position: currentTime, duration: duration))
        let position = finished == true && duration > 0 ? duration : currentTime
        _ = try? progressStore.save(
            itemID: libraryItemID,
            position: position,
            duration: duration,
            isFinished: finished
        )
        lastProgressSaveDate = Date()
        lastSavedPosition = currentTime
    }

    // MARK: - Observers

    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                guard let self, seconds.isFinite else { return }
                self.currentTime = seconds
                if self.duration <= 0,
                   let itemDuration = self.player.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                self.persistProgress()
            }
        }
    }

    private func addTimeControlObserver() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observed, _ in
            let status = observed.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .playing:
                    if self.currentItem != nil,
                       self.phase == .buffering
                        || self.phase == .paused
                        || self.phase == .ready
                        || self.phase == .interrupted {
                        self.phase = .playing
                    }
                case .waitingToPlayAtSpecifiedRate:
                    if self.phase == .playing {
                        self.phase = .buffering
                    }
                case .paused:
                    // Do not fight an explicit play() request that is still
                    // waiting for the item to become ready. End/interruption
                    // paths set the phase themselves.
                    break
                @unknown default:
                    break
                }
            }
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

        mediaServicesResetObserver = center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMediaServicesReset()
            }
        }
        #endif
    }

    #if os(iOS)
    private func activateAudioSession() {
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay])
                try session.setActive(true)
            } catch {
                let message = LocalPodLocalization.format(
                    "playback.error.audioSession",
                    error.localizedDescription
                )
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
            if isPlaying {
                pause(userInitiated: false)
                phase = .interrupted
            }
            persistProgress(force: true)
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            let shouldResume = PlaybackPolicy.shouldResumeAfterInterruption(
                wasPlaying: wasPlayingBeforeInterruption,
                optionsContainShouldResume: options.contains(.shouldResume)
            )
            let wasPlaying = wasPlayingBeforeInterruption
            wasPlayingBeforeInterruption = false
            if shouldResume {
                play()
            } else if wasPlaying {
                phase = .paused
                updateNowPlaying()
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
        if reason == .oldDeviceUnavailable, isPlaying {
            pause(userInitiated: false)
            phase = .paused
        }
    }

    private func handleMediaServicesReset() {
        guard let item = currentItem else { return }
        let position = currentTime
        let wasPlaying = isPlaying
        persistProgress(force: true)
        didRecordPlayStart = true // do not count a second play
        playIntent = wasPlaying
        installPlayerItem(for: item, seek: position, autoplay: wasPlaying)
    }
    #else
    private func activateAudioSession() {
        // AVPlayer on macOS uses the default output device.
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {}

    private func handleRouteChange(reasonRaw: UInt?) {}

    private func handleMediaServicesReset() {}
    #endif

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForwardInterval)]
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackwardInterval)]
        center.changePlaybackPositionCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true

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
            Task { @MainActor [weak self] in
                guard let self else { return }
                let interval = (event as? MPSkipIntervalCommandEvent)?.interval
                    ?? self.skipForwardInterval
                self.skip(by: interval)
            }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let interval = (event as? MPSkipIntervalCommandEvent)?.interval
                    ?? self.skipBackwardInterval
                self.skip(by: -interval)
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onNextTrack?() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onPreviousTrack?() }
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

    private func updateNowPlaying() {
        guard let item = currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            #if os(iOS)
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            #endif
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.subtitle,
            MPMediaItemPropertyAlbumTitle: item.subtitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: playIntent ? Double(playbackRate) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(playbackRate),
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let artwork = artwork(for: item) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(iOS)
        MPNowPlayingInfoCenter.default().playbackState = playIntent
            ? .playing
            : (phase == .ended || phase == .idle ? .stopped : .paused)
        #endif
    }

    #if os(iOS)
    private func artwork(for item: PlaybackItem) -> MPMediaItemArtwork? {
        let key = item.artworkURL?.path
            ?? "placeholder-\(item.kind.rawValue)"
        if cachedArtworkKey == key, let cachedArtwork {
            return cachedArtwork
        }
        let artwork = Self.makeArtwork(item: item)
        cachedArtworkKey = key
        cachedArtwork = artwork
        return artwork
    }

    /// MediaPlayer calls the request handler on a background queue. Reading the
    /// JPEG and creating the image here keeps the closure free of main-actor
    /// state.
    nonisolated private static func makeArtwork(item: PlaybackItem) -> MPMediaItemArtwork {
        var sourceImage: UIImage?
        if let artworkURL = item.artworkURL,
           let data = try? Data(contentsOf: artworkURL) {
            sourceImage = UIImage(data: data)
        }
        if let sourceImage {
            return MPMediaItemArtwork(boundsSize: sourceImage.size) { _ in sourceImage }
        }
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
            if let symbol = UIImage(systemName: "waveform.circle.fill")?.withTintColor(
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
