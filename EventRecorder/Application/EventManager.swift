import Foundation

@MainActor
public final class EventManager: ObservableObject {
    @Published public private(set) var events: [EventEntry] = []
    @Published public private(set) var message: String?
    @Published public private(set) var reminderPermissionStatus: ReminderPermissionStatus = .notDetermined

    private let store: EventStoreProtocol
    private let reminderService: ReminderServiceProtocol
    private let browserController: BrowserWindowControlling
    private let nowProvider: () -> Date
    private var didLaunchStartupBrowser = false

    public init(
        store: EventStoreProtocol = EventStore(),
        reminderService: ReminderServiceProtocol? = nil,
        browserController: BrowserWindowControlling,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.reminderService = reminderService ?? ReminderService()
        self.browserController = browserController
        self.nowProvider = nowProvider
    }

    public func prepare() async {
        launchStartupBrowserIfNeeded()
        await refreshPermissionStatus()
        do {
            events = try store.load()
        } catch {
            message = error.localizedDescription
        }
    }

    public func launchStartupBrowserIfNeeded() {
        guard !didLaunchStartupBrowser else {
            return
        }
        browserController.openStartupBrowserIfNeeded()
        didLaunchStartupBrowser = true
    }

    public func requestNotificationPermission() async {
        let granted = await reminderService.requestPermission()
        await refreshPermissionStatus()
        message = granted ? "通知を許可しました。" : "通知が許可されていません。"
    }

    public func addEvent(
        title: String?,
        urlText: String,
        startsAt: Date,
        endsAt: Date
    ) async {
        let normalizedURLText = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalizedURLText) else {
            message = EventEntryValidationError.invalidURLScheme(urlText).localizedDescription
            return
        }

        do {
            let event = try EventEntry(
                title: title,
                url: url,
                startsAt: startsAt,
                endsAt: endsAt
            ).validated()

            events = try store.add(event: event)
            let scheduleResult = try await reminderService.scheduleReminder(for: event, now: nowProvider())

            switch scheduleResult {
            case .scheduled(let date):
                message = "イベントを追加し、\(Self.dateFormatter.string(from: date)) に通知を設定しました。"
            case .skippedPastLeadTime:
                message = "イベントを追加しました。開始10分前を過ぎているため通知は設定しませんでした。"
            }
        } catch {
            message = error.localizedDescription
        }
    }

    public func deleteEvent(id: UUID) async {
        guard let event = events.first(where: { $0.id == id }) else {
            return
        }

        await reminderService.cancelReminder(for: event)

        do {
            events = try store.delete(id: id)
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    public func open(_ event: EventEntry) {
        browserController.open(url: event.url)
    }

    public func openFullScreen(_ event: EventEntry) {
        browserController.openFullScreen(url: event.url)
    }

    public func toggleBrowserFullScreen() {
        browserController.toggleFullScreen()
    }

    public func openFromNotification(urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }
        browserController.open(url: url)
    }

    private func refreshPermissionStatus() async {
        reminderPermissionStatus = await reminderService.permissionStatus()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
}
