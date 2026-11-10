import XCTest
@testable import LocalPodKit

final class SigningReminderScheduleTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    }

    override func tearDown() {
        calendar = nil
        super.tearDown()
    }

    func testScheduleFiresTwoDaysBeforeExpiryAtTenLocal() throws {
        let now = try date(2026, 6, 1, 12, 0)
        let expiry = try date(2026, 6, 10, 15, 30)

        let schedule = try XCTUnwrap(SigningReminderSchedule.makeSchedule(
            expirationDate: expiry,
            isEnabled: true,
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(schedule.identifier, SigningReminderSchedule.notificationIdentifier)
        XCTAssertEqual(schedule.expirationDate, expiry)
        XCTAssertEqual(schedule.daysRemaining, 9)
        XCTAssertEqual(
            calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: schedule.fireDate
            ),
            DateComponents(year: 2026, month: 6, day: 8, hour: 10, minute: 0)
        )
    }

    func testPastExpiryReturnsNoSchedule() throws {
        let now = try date(2026, 6, 10, 12, 0)
        let expiry = try date(2026, 6, 10, 9, 0)

        XCTAssertNil(SigningReminderSchedule.makeSchedule(
            expirationDate: expiry,
            isEnabled: true,
            now: now,
            calendar: calendar
        ))
    }

    func testDisabledReturnsNoSchedule() throws {
        let now = try date(2026, 6, 1, 12, 0)
        let expiry = try date(2026, 6, 10, 15, 30)

        XCTAssertNil(SigningReminderSchedule.makeSchedule(
            expirationDate: expiry,
            isEnabled: false,
            now: now,
            calendar: calendar
        ))
    }

    func testMissingExpiryReturnsNoSchedule() throws {
        let now = try date(2026, 6, 1, 12, 0)

        XCTAssertNil(SigningReminderSchedule.makeSchedule(
            expirationDate: nil,
            isEnabled: true,
            now: now,
            calendar: calendar
        ))
    }

    func testFireTimeAlreadyPassedReturnsNoSchedule() throws {
        // The reminder would have fired on June 8 at 10:00; by June 9 there is
        // nothing left to schedule. The profile itself is still valid.
        let now = try date(2026, 6, 9, 11, 0)
        let expiry = try date(2026, 6, 10, 15, 30)

        XCTAssertNil(SigningReminderSchedule.makeSchedule(
            expirationDate: expiry,
            isEnabled: true,
            now: now,
            calendar: calendar
        ))
    }

    func testIdentifierIsStableSoNewScheduleReplacesPriorRequest() throws {
        let now = try date(2026, 6, 1, 12, 0)
        let first = try XCTUnwrap(SigningReminderSchedule.makeSchedule(
            expirationDate: try date(2026, 6, 10, 15, 30),
            isEnabled: true,
            now: now,
            calendar: calendar
        ))
        let second = try XCTUnwrap(SigningReminderSchedule.makeSchedule(
            expirationDate: try date(2026, 6, 12, 15, 30),
            isEnabled: true,
            now: now,
            calendar: calendar
        ))

        // UNUserNotificationCenter replaces a pending request whose identifier
        // matches, so both schedules must use the same stable identifier.
        XCTAssertEqual(first.identifier, second.identifier)
        XCTAssertEqual(first.identifier, "localpod.signing.expiry")
        XCTAssertNotEqual(first.fireDate, second.fireDate)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }
}
