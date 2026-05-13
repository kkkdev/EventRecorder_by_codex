import Foundation

public enum ReminderScheduling {
    public static let defaultLeadTimeSeconds: TimeInterval = 10 * 60

    public static func reminderDate(
        for startDate: Date,
        now: Date = Date(),
        leadTimeSeconds: TimeInterval = defaultLeadTimeSeconds
    ) -> Date? {
        let reminderDate = startDate.addingTimeInterval(-leadTimeSeconds)
        return reminderDate > now ? reminderDate : nil
    }
}
