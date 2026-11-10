import Foundation

/// Pure date math for the local signing-expiry reminder. The app target owns
/// the `UNUserNotificationCenter` wrapper; keeping the calendar rules here
/// makes them deterministic and unit-testable on any platform.
public enum SigningReminderSchedule {
    /// Stable request identifier. Adding a request with the same identifier
    /// replaces the previously pending one, so repeated launches cannot stack
    /// duplicate reminders.
    public static let notificationIdentifier = "localpod.signing.expiry"
    public static let leadTimeDays = 2
    public static let reminderHour = 10

    public struct Schedule: Equatable, Sendable {
        public let identifier: String
        public let expirationDate: Date
        public let fireDate: Date
        public let daysRemaining: Int

        public init(
            identifier: String,
            expirationDate: Date,
            fireDate: Date,
            daysRemaining: Int
        ) {
            self.identifier = identifier
            self.expirationDate = expirationDate
            self.fireDate = fireDate
            self.daysRemaining = daysRemaining
        }
    }

    /// Returns the reminder to schedule, or nil when reminders are disabled,
    /// there is no profile expiry, the profile is already expired, or the
    /// ideal fire time (expiry minus two days at 10:00 local) has passed.
    public static func makeSchedule(
        expirationDate: Date?,
        isEnabled: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> Schedule? {
        guard isEnabled, let expirationDate, expirationDate > now else {
            return nil
        }

        let expirationDay = calendar.startOfDay(for: expirationDate)
        guard let leadDay = calendar.date(
            byAdding: .day,
            value: -leadTimeDays,
            to: expirationDay
        ),
        let fireDate = calendar.date(
            bySettingHour: reminderHour,
            minute: 0,
            second: 0,
            of: leadDay
        ) else {
            return nil
        }

        // A profile that expires tomorrow cannot be reminded two days before;
        // the in-app Diagnostics banner remains the fallback.
        guard fireDate > now else { return nil }

        let daysRemaining = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: expirationDay
        ).day ?? 0

        return Schedule(
            identifier: notificationIdentifier,
            expirationDate: expirationDate,
            fireDate: fireDate,
            daysRemaining: daysRemaining
        )
    }
}
