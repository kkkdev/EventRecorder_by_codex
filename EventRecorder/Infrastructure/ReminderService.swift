import Foundation
import UserNotifications

public enum ReminderScheduleResult: Equatable {
    case scheduled(Date)
    case skippedPastLeadTime
}

public enum ReminderPermissionStatus: String {
    case notDetermined
    case denied
    case authorized
}

@MainActor
public protocol ReminderServiceProtocol {
    func permissionStatus() async -> ReminderPermissionStatus
    func requestPermission() async -> Bool
    func scheduleReminder(for event: EventEntry, now: Date) async throws -> ReminderScheduleResult
    func cancelReminder(for event: EventEntry) async
}

public enum ReminderServiceError: LocalizedError {
    case notificationPermissionDenied
    case schedulingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notificationPermissionDenied:
            return "通知権限がありません。システム設定で許可してください。"
        case .schedulingFailed(let reason):
            return "通知スケジュールに失敗しました: \(reason)"
        }
    }
}

@MainActor
public final class ReminderService: ReminderServiceProtocol {
    nonisolated public static let categoryIdentifier = "EVENT_REMINDER_CATEGORY"
    nonisolated public static let openActionIdentifier = "EVENT_REMINDER_OPEN"
    nonisolated public static let eventURLUserInfoKey = "event_url"

    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        registerCategory()
    }

    public func permissionStatus() async -> ReminderPermissionStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        default:
            return .notDetermined
        }
    }

    public func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    public func scheduleReminder(for event: EventEntry, now: Date = Date()) async throws -> ReminderScheduleResult {
        guard await hasPermission() else {
            throw ReminderServiceError.notificationPermissionDenied
        }

        guard let reminderDate = ReminderScheduling.reminderDate(for: event.startsAt, now: now) else {
            await cancelReminder(for: event)
            return .skippedPastLeadTime
        }

        let content = UNMutableNotificationContent()
        content.title = "イベント開始10分前"
        content.body = "\(event.displayTitle) がまもなく開始します。"
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [Self.eventURLUserInfoKey: event.url.absoluteString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: event.notificationID,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            return .scheduled(reminderDate)
        } catch {
            throw ReminderServiceError.schedulingFailed(error.localizedDescription)
        }
    }

    public func cancelReminder(for event: EventEntry) async {
        center.removePendingNotificationRequests(withIdentifiers: [event.notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [event.notificationID])
    }

    private func hasPermission() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private func registerCategory() {
        let openAction = UNNotificationAction(
            identifier: Self.openActionIdentifier,
            title: "開く",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }
}
