import Foundation
import UserNotifications

final class EventReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onOpenURL: ((String) -> Void)?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let action = response.actionIdentifier
        let isOpenAction = action == ReminderService.openActionIdentifier || action == UNNotificationDefaultActionIdentifier
        guard isOpenAction else {
            return
        }

        guard let url = response.notification.request.content.userInfo[ReminderService.eventURLUserInfoKey] as? String else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onOpenURL?(url)
        }
    }
}
