import Foundation
import UserNotifications
import LocalPodKit

/// Delivers the local "import finished/failed" notification.
///
/// This is the same local-only lane as `SigningReminder`: no push entitlement,
/// no remote notifications, and no notification actions. Delivery reuses the
/// existing `SigningNotificationCenter` seam so tests can substitute a fake
/// center without touching `UNUserNotificationCenter`.
@MainActor
enum ImportNotifier {
    struct Content: Equatable {
        let title: String
        let body: String
    }

    /// UI-test seam: the last decision is published here (DEBUG only) so a UI
    /// test can assert the real policy/wiring result without notification
    /// permission. Settings surfaces the value under
    /// `lastImportNotificationText`.
    static let debugLastDecisionDefaultsKey = "p2.lastImportNotification"

    /// The only path that requests notification permission. Called when the
    /// user turns the Settings toggle on, never at launch.
    static func requestAuthorization(
        center: any SigningNotificationCenter = UNUserNotificationCenter.current()
    ) async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Delivers an already-decided notification. Authorization is checked
    /// here (not in the pure kit policy) and a not-yet-determined status is
    /// skipped silently — enabling the toggle is what triggers the prompt.
    static func notify(
        decision: ImportNotificationDecision,
        center: any SigningNotificationCenter = UNUserNotificationCenter.current()
    ) async {
        #if DEBUG
        publishDebugDecisionIfRequested(decision)
        #endif

        guard let content = content(for: decision) else { return }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.body = content.body
        notification.sound = .default

        // nil trigger = deliver immediately. A unique identifier keeps each
        // finished run as its own notification instead of replacing the last.
        let request = UNNotificationRequest(
            identifier: "import-notification-\(UUID().uuidString)",
            content: notification,
            trigger: nil
        )
        try? await center.add(request)
    }

    static func content(for decision: ImportNotificationDecision) -> Content? {
        switch decision {
        case .none:
            return nil
        case let .notifySuccess(importedCount, relinkedCount, collectionName):
            return Content(
                title: L10n.string("notification.import.success.title"),
                body: L10n.format(
                    "notification.import.success.body",
                    collectionName,
                    importedCount + relinkedCount
                )
            )
        case let .notifyFailure(message):
            let detail = message?.trimmingCharacters(in: .whitespacesAndNewlines)
            let body: String
            if let detail, !detail.isEmpty {
                body = detail
            } else {
                body = L10n.string("notification.import.failure.body")
            }
            return Content(
                title: L10n.string("notification.import.failure.title"),
                body: body
            )
        }
    }

    #if DEBUG
    private static func publishDebugDecisionIfRequested(
        _ decision: ImportNotificationDecision
    ) {
        guard ProcessInfo.processInfo.arguments.contains("--p2-print-import-notification")
        else {
            return
        }
        let description = content(for: decision)
            .map { "\($0.title)：\($0.body)" } ?? "none"
        UserDefaults.standard.set(description, forKey: debugLastDecisionDefaultsKey)
        print("[ImportNotifier] \(description)")
    }
    #endif
}
