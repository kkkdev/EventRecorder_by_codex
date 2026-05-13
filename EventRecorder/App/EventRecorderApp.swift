import SwiftUI
import UserNotifications

@MainActor
final class AppContainer: ObservableObject {
    let captureController: CaptureSessionController
    let eventManager: EventManager

    private let browserController: BrowserWindowController
    private let reminderService: ReminderService
    private let notificationDelegate: EventReminderNotificationDelegate

    init() {
        captureController = CaptureSessionController()
        browserController = BrowserWindowController()
        reminderService = ReminderService()
        eventManager = EventManager(
            store: EventStore(),
            reminderService: reminderService,
            browserController: browserController
        )

        notificationDelegate = EventReminderNotificationDelegate()
        notificationDelegate.onOpenURL = { [weak self] url in
            self?.eventManager.openFromNotification(urlString: url)
        }

        UNUserNotificationCenter.current().delegate = notificationDelegate
    }
}

@main
struct EventRecorderApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            MainView(
                controller: container.captureController,
                eventManager: container.eventManager
            )
            .frame(minWidth: 780, minHeight: 620)
        }
    }
}
