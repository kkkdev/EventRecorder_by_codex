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
        UNUserNotificationCenter.current().add(request) { error in
            guard let error else {
                return
            }
            let record = CaptureErrorRecord(error: error)
            CaptureLog.teams.error(
                "automatic capture notification failed domain=\(record.domain, privacy: .public) code=\(record.code, privacy: .public)"
            )
        }
    }
}
