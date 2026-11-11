import Foundation

/// A minimal, app-independent snapshot of one import run.
///
/// `ImportCoordinator.RunSummary` lives in the app target, so the coordinator
/// maps its summary into this value before asking the policy for a decision.
/// Keeping the policy in the package makes the notification rules testable
/// without UserNotifications or UIKit.
public struct ImportNotificationSummary: Equatable, Sendable {
    public var collectionName: String
    public var importedCount: Int
    public var relinkedCount: Int
    public var failedCount: Int
    public var cancelled: Bool
    public var firstIssueMessage: String?

    public init(
        collectionName: String,
        importedCount: Int,
        relinkedCount: Int,
        failedCount: Int,
        cancelled: Bool,
        firstIssueMessage: String? = nil
    ) {
        self.collectionName = collectionName
        self.importedCount = importedCount
        self.relinkedCount = relinkedCount
        self.failedCount = failedCount
        self.cancelled = cancelled
        self.firstIssueMessage = firstIssueMessage
    }

    /// Imported and relinked files both mean "this run produced usable media".
    public var successCount: Int {
        importedCount + relinkedCount
    }
}

/// What (if anything) to tell the user about a finished import run.
public enum ImportNotificationDecision: Equatable, Sendable {
    case notifySuccess(importedCount: Int, relinkedCount: Int, collectionName: String)
    case notifyFailure(message: String?)
    case none
}

/// Pure decision rules for the local "import finished/failed" notification.
///
/// Local-only by design: no push entitlement, no remote notifications, and no
/// notification actions. The app target owns authorization, content strings,
/// and delivery; this type only decides whether a run is worth surfacing.
public enum ImportNotificationPolicy {
    /// - Parameters:
    ///   - summary: The finished run, or nil when the run failed before a
    ///     summary could be built (and for user cancellations).
    ///   - errorMessage: A hard failure's localized description.
    ///   - isAppActive: True while the app is in the foreground. The import UI
    ///     already shows the result there, so a banner would be noise.
    ///   - isEnabled: The user's Settings toggle. Disabled always wins.
    public static func decision(
        summary: ImportNotificationSummary?,
        errorMessage: String?,
        isAppActive: Bool,
        isEnabled: Bool
    ) -> ImportNotificationDecision {
        // Opting out and foreground suppression apply to every outcome,
        // including hard failures.
        guard isEnabled, !isAppActive else { return .none }

        // A thrown error means no summary was produced; report it as a
        // failure even before looking at counts.
        if let errorMessage = normalized(errorMessage) {
            return .notifyFailure(message: errorMessage)
        }

        guard let summary, !summary.cancelled else { return .none }

        // Partial success still counts as success: the user has new media to
        // listen to, and the import screen/report covers the failed files.
        if summary.successCount > 0 {
            return .notifySuccess(
                importedCount: summary.importedCount,
                relinkedCount: summary.relinkedCount,
                collectionName: summary.collectionName
            )
        }

        // A run that imported nothing but failed files is a failure. A run
        // that imported nothing and failed nothing (all duplicates, all
        // unsupported) is not worth a notification.
        if summary.failedCount > 0 {
            return .notifyFailure(message: normalized(summary.firstIssueMessage))
        }

        return .none
    }

    private static func normalized(_ message: String?) -> String? {
        guard let message else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
