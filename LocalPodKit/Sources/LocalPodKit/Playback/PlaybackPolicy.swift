import Foundation

/// Pure playback rules shared by the controller, UI and tests. Keeping these
/// decisions free of AVFoundation makes resume/completion behavior deterministic
/// and unit-testable.
public enum PlaybackPolicy {
    /// Presets exposed in the player. 0.5/1.0/1.5/2.0/3.0 are required by M2.
    public static let speedPresets: [Float] = [
        0.5, 0.8, 1.0, 1.2, 1.5, 1.8, 2.0, 2.5, 3.0
    ]

    /// One-tap chips in the player. All supported speeds are featured so the
    /// owner can reach the intermediate steps (0.8/1.2/1.8/2.5) without a
    /// hidden menu; the row scrolls horizontally when it does not fit.
    public static let featuredSpeedPresets: [Float] = speedPresets

    public static let minimumSpeed: Float = 0.5
    public static let maximumSpeed: Float = 3.0

    /// Resume only when the saved position is meaningfully inside the episode.
    public static let minimumResumePosition: Double = 3
    /// Do not resume if the remaining time is this short; start over instead.
    public static let resumeTailWindow: Double = 30

    /// Completion: at least 95%, or (for podcast-length media) the last 30s.
    public static let completionFraction: Double = 0.95
    public static let completionTailWindow: Double = 30
    /// The "last 30 seconds" rule only makes sense for media longer than this;
    /// otherwise a 20-second clip would be finished before it starts.
    public static let completionTailMinimumDuration: Double = 60

    public static func clampedRate(_ rate: Float) -> Float {
        guard rate.isFinite else { return 1 }
        return min(max(rate, minimumSpeed), maximumSpeed)
    }

    public static func speedLabel(_ rate: Float) -> String {
        String(format: "%.1f×", clampedRate(rate))
    }

    public static func isFinished(position: Double, duration: Double) -> Bool {
        guard position.isFinite, duration.isFinite, duration > 0 else {
            return false
        }
        let clampedPosition = min(max(position, 0), duration)
        if clampedPosition >= duration * completionFraction {
            return true
        }
        if duration > completionTailMinimumDuration,
           duration - clampedPosition <= completionTailWindow {
            return true
        }
        return false
    }

    public static func shouldResume(
        position: Double,
        duration: Double,
        isFinished: Bool
    ) -> Bool {
        guard !isFinished,
              position.isFinite,
              duration.isFinite,
              duration > 0,
              position > minimumResumePosition else {
            return false
        }
        return position < duration - resumeTailWindow
    }

    public static func resumePosition(
        position: Double,
        duration: Double,
        isFinished: Bool
    ) -> Double {
        shouldResume(position: position, duration: duration, isFinished: isFinished)
            ? min(max(position, 0), duration)
            : 0
    }

    public static func shouldResumeAfterInterruption(
        wasPlaying: Bool,
        optionsContainShouldResume: Bool
    ) -> Bool {
        wasPlaying && optionsContainShouldResume
    }
}
