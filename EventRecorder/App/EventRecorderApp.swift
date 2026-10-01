import SwiftUI
import UserNotifications
import AppKit

@MainActor
final class AppContainer: ObservableObject {
    let captureController: CaptureSessionController
    let eventManager: EventManager
    let teamsAutomationController: TeamsAutomationController

    private let browserController: BrowserWindowController
    private let reminderService: ReminderService
    private let notificationDelegate: EventReminderNotificationDelegate
    private var sleepObserver: NSObjectProtocol?

    init() {
        captureController = CaptureSessionController()
        browserController = BrowserWindowController()
        reminderService = ReminderService()
        eventManager = EventManager(
            store: EventStore(),
            reminderService: reminderService,
            browserController: browserController
        )
        teamsAutomationController = TeamsAutomationController(
            captureController: captureController
        )

        notificationDelegate = EventReminderNotificationDelegate()
        notificationDelegate.onOpenURL = { [weak self] url in
            self?.eventManager.openFromNotification(urlString: url)
        }

        UNUserNotificationCenter.current().delegate = notificationDelegate

        let automationController = teamsAutomationController
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await automationController.handleSystemWillSleep()
            }
        }
    }

    deinit {
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
    }
}

@main
struct EventRecorderApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            MainView(
                controller: container.captureController,
                eventManager: container.eventManager,
                teamsAutomationController: container.teamsAutomationController
            )
            .frame(minWidth: 780, minHeight: 620)
        }
    }
}
