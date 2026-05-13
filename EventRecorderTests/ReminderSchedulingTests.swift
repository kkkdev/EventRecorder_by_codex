import Foundation
import XCTest
@testable import EventRecorderCore

final class ReminderSchedulingTests: XCTestCase {
    func testReminderDateReturnsTenMinutesBeforeStart() {
        let now = date("2026-02-12T10:00:00Z")
        let start = date("2026-02-12T11:00:00Z")

        let reminder = ReminderScheduling.reminderDate(for: start, now: now)
        XCTAssertEqual(reminder, date("2026-02-12T10:50:00Z"))
    }

    func testReminderDateReturnsNilWhenLeadTimeAlreadyPassed() {
        let now = date("2026-02-12T10:55:00Z")
        let start = date("2026-02-12T11:00:00Z")

        let reminder = ReminderScheduling.reminderDate(for: start, now: now)
        XCTAssertNil(reminder)
    }

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }
}
