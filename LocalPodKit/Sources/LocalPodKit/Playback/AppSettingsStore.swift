import Foundation

/// UserDefaults-backed playback settings. Every setter writes immediately, so
/// settings survive termination without a separate save action.
@MainActor
@Observable
public final class AppSettingsStore {
    public static let defaultKeyPrefix = "localpod.settings."
    public static let skipOptions: [Double] = [10, 15, 30, 45, 60]

    public static let keyDefaultRate = "defaultRate"
    public static let keySkipForward = "skipForward"
    public static let keySkipBackward = "skipBackward"
    public static let keyResumeEnabled = "resumeEnabled"
    public static let keyAutoPlayNext = "autoPlayNext"

    public var defaultRate: Float {
        didSet { defaults.set(Double(defaultRate), forKey: key(Self.keyDefaultRate)) }
    }
    public var skipForwardSeconds: Double {
        didSet { defaults.set(skipForwardSeconds, forKey: key(Self.keySkipForward)) }
    }
    public var skipBackwardSeconds: Double {
        didSet { defaults.set(skipBackwardSeconds, forKey: key(Self.keySkipBackward)) }
    }
    /// When false, a newly loaded item starts at 0 even if saved progress
    /// exists. Progress is still recorded.
    public var resumeEnabled: Bool {
        didSet { defaults.set(resumeEnabled, forKey: key(Self.keyResumeEnabled)) }
    }
    /// Auto-advance the queue when an item ends.
    public var autoPlayNext: Bool {
        didSet { defaults.set(autoPlayNext, forKey: key(Self.keyAutoPlayNext)) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let prefix: String

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = AppSettingsStore.defaultKeyPrefix
    ) {
        self.defaults = defaults
        self.prefix = keyPrefix

        let storedRate = defaults.object(forKey: keyPrefix + Self.keyDefaultRate)
            as? Double ?? 1.0
        let storedForward = defaults.object(forKey: keyPrefix + Self.keySkipForward)
            as? Double ?? 15
        let storedBackward = defaults.object(forKey: keyPrefix + Self.keySkipBackward)
            as? Double ?? 15
        let storedResume = defaults.object(forKey: keyPrefix + Self.keyResumeEnabled)
            as? Bool ?? true
        let storedAutoNext = defaults.object(forKey: keyPrefix + Self.keyAutoPlayNext)
            as? Bool ?? true

        defaultRate = PlaybackPolicy.clampedRate(Float(storedRate))
        skipForwardSeconds = Self.validSkip(storedForward)
        skipBackwardSeconds = Self.validSkip(storedBackward)
        resumeEnabled = storedResume
        autoPlayNext = storedAutoNext
    }

    public func reset() {
        for key in [
            Self.keyDefaultRate,
            Self.keySkipForward,
            Self.keySkipBackward,
            Self.keyResumeEnabled,
            Self.keyAutoPlayNext
        ] {
            defaults.removeObject(forKey: prefix + key)
        }
        defaultRate = 1.0
        skipForwardSeconds = 15
        skipBackwardSeconds = 15
        resumeEnabled = true
        autoPlayNext = true
    }

    public static func clearStoredValues(
        defaults: UserDefaults = .standard,
        keyPrefix: String = AppSettingsStore.defaultKeyPrefix
    ) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func key(_ name: String) -> String {
        prefix + name
    }

    private static func validSkip(_ value: Double) -> Double {
        guard value.isFinite else { return 15 }
        return min(max(value, 5), 120)
    }
}
