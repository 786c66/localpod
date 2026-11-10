import Foundation

/// Sleep timer with minute countdowns, end-of-episode mode and a fade-out.
///
/// The fade callback reports a player volume multiplier in `1...0`. The app
/// restores volume after the timer fires. `tick(now:)` is exposed for tests so
/// countdown behavior can be verified without wall-clock waits.
@MainActor
@Observable
public final class SleepTimer {
    public enum Mode: Equatable, Sendable {
        case off
        case minutes(Int)
        case endOfEpisode

        public var isActive: Bool { self != .off }

        public var displayName: String {
            displayName(locale: nil)
        }

        public func displayName(locale: Locale?) -> String {
            switch self {
            case .off:
                LocalPodLocalization.string("sleep.mode.off", locale: locale)
            case .minutes(let minutes):
                LocalPodLocalization.format(
                    "sleep.mode.minutes",
                    locale: locale,
                    minutes
                )
            case .endOfEpisode:
                LocalPodLocalization.string("sleep.mode.endOfEpisode", locale: locale)
            }
        }
    }

    public private(set) var mode: Mode = .off
    public private(set) var remainingSeconds: TimeInterval?
    public private(set) var isFading = false

    /// Fade starts this many seconds before the deadline.
    public var fadeDuration: TimeInterval = 10

    @ObservationIgnored public var onVolumeChange: ((Float) -> Void)?
    @ObservationIgnored public var onFire: (() -> Void)?
    @ObservationIgnored public var now: () -> Date

    @ObservationIgnored private var deadline: Date?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public var isActive: Bool { mode.isActive }

    public var remainingText: String? {
        guard let remainingSeconds else { return nil }
        let total = max(0, Int(remainingSeconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    public func start(minutes: Int) {
        let clamped = min(max(minutes, 1), 180)
        mode = .minutes(clamped)
        deadline = now().addingTimeInterval(TimeInterval(clamped * 60))
        remainingSeconds = TimeInterval(clamped * 60)
        isFading = false
        startTicker()
    }

    public func startEndOfEpisode() {
        stopTicker()
        deadline = nil
        remainingSeconds = nil
        isFading = false
        mode = .endOfEpisode
        onVolumeChange?(1)
    }

    public func cancel() {
        let wasFading = isFading
        stopTicker()
        deadline = nil
        remainingSeconds = nil
        isFading = false
        mode = .off
        if wasFading {
            onVolumeChange?(1)
        }
    }

    /// Called by the playback session at end of episode. Returns true when the
    /// session must suppress auto-advance.
    public func consumeEndOfEpisode() -> Bool {
        guard mode == .endOfEpisode else { return false }
        cancel()
        return true
    }

    public func tick(now date: Date) {
        guard case .minutes = mode, let deadline else { return }
        let remaining = deadline.timeIntervalSince(date)
        remainingSeconds = max(0, remaining)

        if remaining <= 0 {
            isFading = true
            onVolumeChange?(0)
            let fire = onFire
            stopTicker()
            self.deadline = nil
            remainingSeconds = 0
            mode = .off
            isFading = false
            fire?()
            return
        }

        guard remaining <= fadeDuration, fadeDuration > 0 else {
            if isFading {
                isFading = false
                onVolumeChange?(1)
            }
            return
        }
        isFading = true
        onVolumeChange?(Float(max(0, min(1, remaining / fadeDuration))))
    }

    private func startTicker() {
        stopTicker()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled, let self else { return }
                self.tick(now: self.now())
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
