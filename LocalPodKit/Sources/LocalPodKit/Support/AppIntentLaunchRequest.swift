import Foundation

/// A request handed from an App Intent to the app process. Intents run in the
/// app's process for this app (no extension target), but the request still
/// travels through UserDefaults so it survives a cold launch and always flows
/// through the same consumption path as URL opens.
public enum AppIntentLaunchRequest: Equatable, Sendable {
    case continuePlayback
    case openCollection(name: String)

    private static let continuePlaybackCode = "continue-playback"
    private static let openCollectionPrefix = "open-collection:"

    /// Parses the persisted/launch-argument form. Collection names may contain
    /// colons; only the first colon separates the code from the name.
    public init?(rawValue: String) {
        if rawValue == Self.continuePlaybackCode {
            self = .continuePlayback
            return
        }
        guard rawValue.hasPrefix(Self.openCollectionPrefix) else { return nil }
        let name = String(rawValue.dropFirst(Self.openCollectionPrefix.count))
        guard !name.isEmpty else { return nil }
        self = .openCollection(name: name)
    }

    public var rawValue: String {
        switch self {
        case .continuePlayback:
            Self.continuePlaybackCode
        case .openCollection(let name):
            Self.openCollectionPrefix + name
        }
    }

    /// Parses `localpod://play` and `localpod://collection?name=<name>`.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "localpod",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch components.host?.lowercased() {
        case "play":
            self = .continuePlayback
        case "collection":
            guard let name = components.queryItems?
                .first(where: { $0.name == "name" })?
                .value,
                !name.isEmpty else {
                return nil
            }
            self = .openCollection(name: name)
        default:
            return nil
        }
    }
}

/// Small UserDefaults-backed mailbox for the pending App Intent request.
public enum AppIntentLaunchRequestStore {
    public static let defaultsKey = "p2.pendingAppIntentRequest"

    public static func save(
        _ request: AppIntentLaunchRequest,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(request.rawValue, forKey: defaultsKey)
    }

    public static func peek(defaults: UserDefaults = .standard) -> AppIntentLaunchRequest? {
        guard let rawValue = defaults.string(forKey: defaultsKey) else { return nil }
        return AppIntentLaunchRequest(rawValue: rawValue)
    }

    /// Reads and removes the request so it is handled exactly once.
    public static func consume(defaults: UserDefaults = .standard) -> AppIntentLaunchRequest? {
        let request = peek(defaults: defaults)
        defaults.removeObject(forKey: defaultsKey)
        return request
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
