import Foundation
import XCTest

#if canImport(EventRecorder)
@testable import EventRecorder

@MainActor
final class EventManagerStartupBrowserTests: XCTestCase {
    func testPrepareLaunchesStartupBrowserOnlyOnce() async {
        let browser = MockBrowserWindowController()
        let manager = EventManager(
            store: MockEventStore(),
            reminderService: MockReminderService(),
            browserController: browser,
            nowProvider: Date.init
        )

        await manager.prepare()
        await manager.prepare()

        XCTAssertEqual(browser.openStartupBrowserIfNeededCallCount, 1)
        XCTAssertTrue(browser.hasWindow)
    }

    func testLaunchStartupBrowserIfNeededIsIdempotent() {
        let browser = MockBrowserWindowController()
        let manager = EventManager(
            store: MockEventStore(),
            reminderService: MockReminderService(),
            browserController: browser,
            nowProvider: Date.init
        )

        manager.launchStartupBrowserIfNeeded()
        manager.launchStartupBrowserIfNeeded()

        XCTAssertEqual(browser.openStartupBrowserIfNeededCallCount, 1)
    }
}

@MainActor
private final class MockReminderService: ReminderServiceProtocol {
    func permissionStatus() async -> ReminderPermissionStatus {
        .notDetermined
    }

    func requestPermission() async -> Bool {
        true
    }

    func scheduleReminder(for event: EventEntry, now: Date) async throws -> ReminderScheduleResult {
        .scheduled(event.startsAt)
    }

    func cancelReminder(for event: EventEntry) async {}
}

private struct MockEventStore: EventStoreProtocol {
    func load() throws -> [EventEntry] { [] }
    func save(events: [EventEntry]) throws {}
    func add(event: EventEntry) throws -> [EventEntry] { [event] }
    func delete(id: UUID) throws -> [EventEntry] { [] }
}

@MainActor
private final class MockBrowserWindowController: BrowserWindowControlling {
    var hasWindow = false
    var openStartupBrowserIfNeededCallCount = 0

    func open(url: URL) {}
    func openFullScreen(url: URL) {}
    func toggleFullScreen() {}

    func openStartupBrowserIfNeeded() {
        openStartupBrowserIfNeededCallCount += 1
        if !hasWindow {
            hasWindow = true
        }
    }
}
#endif
