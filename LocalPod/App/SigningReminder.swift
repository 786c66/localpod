import Foundation
import UserNotifications
import LocalPodKit

/// Thin wrapper around local notifications for the provisioning-profile expiry
/// reminder. There is no push entitlement involved: everything here is a
/// `UNCalendarNotificationTrigger` scheduled on-device.
protocol SigningNotificationCenter: AnyObject, Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func notificationSettings() async -> UNNotificationSettings
}

extension UNUserNotificationCenter: SigningNotificationCenter {}

@MainActor
enum SigningReminder {
    /// Called at launch. It only reads the current authorization status, so a
    /// fresh install never sees a permission prompt until the user opts in
    /// from Settings. If notifications are denied or not yet determined,
    /// scheduling is skipped silently; the Diagnostics banner still works.
    static func refresh(
        expirationDate: Date?,
        isEnabled: Bool,
        center: any SigningNotificationCenter = UNUserNotificationCenter.current(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        guard isEnabled else {
            cancel(center: center)
            return
        }

        guard let schedule = SigningReminderSchedule.makeSchedule(
            expirationDate: expirationDate,
            isEnabled: true,
            now: now,
            calendar: calendar
        ) else {
            // No profile, already expired, or the lead time has passed. Remove
            // any stale request from a previous profile.
            cancel(center: center)
            return
        }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "LocalPod 签名即将到期"
        content.body = "签名将在 2 天后到期，建议在到期前用同一 Bundle ID 重签；重签不会清除资料库。"
        content.sound = .default

        // Leave the time zone unset so the trigger follows the device's local
        // time zone at fire time; the schedule is always "10:00 local".
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: schedule.fireDate
        )
        components.timeZone = nil
        components.calendar = nil
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: schedule.identifier,
            content: content,
            trigger: trigger
        )

        // Same identifier = replacement, so a relaunch or a re-signed profile
        // never leaves two reminders pending.
        try? await center.add(request)
    }

    /// Called when the Settings toggle changes. Enabling is the only path that
    /// requests notification authorization. Disabling cancels the pending
    /// reminder immediately.
    @discardableResult
    static func setEnabled(
        _ isEnabled: Bool,
        expirationDate: Date?,
        center: any SigningNotificationCenter = UNUserNotificationCenter.current(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> Bool {
        guard isEnabled else {
            cancel(center: center)
            return false
        }

        let granted = (try? await center.requestAuthorization(
            options: [.alert, .sound]
        )) ?? false

        if granted {
            await refresh(
                expirationDate: expirationDate,
                isEnabled: true,
                center: center,
                now: now,
                calendar: calendar
            )
        } else {
            // The user declined. Keep the setting enabled so the in-app
            // banner remains the fallback, but do not keep a stale request.
            cancel(center: center)
        }
        return granted
    }

    private static func cancel(center: any SigningNotificationCenter) {
        center.removePendingNotificationRequests(
            withIdentifiers: [SigningReminderSchedule.notificationIdentifier]
        )
    }
}
