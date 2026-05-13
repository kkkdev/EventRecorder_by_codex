import Foundation
import XCTest
@testable import EventRecorderCore

final class EventStoreTests: XCTestCase {
    func testAddLoadDeleteRoundTrip() throws {
        let store = EventStore(storageURL: makeTemporaryFileURL())

        let event = EventEntry(
            title: "sample",
            url: URL(string: "https://example.com")!,
            startsAt: Date().addingTimeInterval(3600),
            endsAt: Date().addingTimeInterval(7200)
        )

        let afterAdd = try store.add(event: event)
        XCTAssertEqual(afterAdd.count, 1)

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, event.id)

        let afterDelete = try store.delete(id: event.id)
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testAddRejectsInvalidURLScheme() {
        let store = EventStore(storageURL: makeTemporaryFileURL())
        let invalid = EventEntry(
            title: nil,
            url: URL(string: "ftp://example.com")!,
            startsAt: Date().addingTimeInterval(3600),
            endsAt: Date().addingTimeInterval(7200)
        )

        XCTAssertThrowsError(try store.add(event: invalid)) { error in
            guard case .invalidURLScheme = error as? EventEntryValidationError else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }
    }

    private func makeTemporaryFileURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("events.json")
    }
}
