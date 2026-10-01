import Foundation
import UserNotifications

public protocol TeamsAutomationNotifying: AnyObject {
    func notifyCaptureWillStart(gracePeriodSeconds: Int)
}

public final class TeamsAutomationNotifier: TeamsAutomationNotifying {
    public init() {}

    public func notifyCaptureWillStart(gracePeriodSeconds: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Teams会議を検出しました"
        content.body = "録画を(gracePeriodSeconds)秒後に開始します。中止する場合はEvent Recorderを開いてください。"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "teams-auto-capture-pending",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
