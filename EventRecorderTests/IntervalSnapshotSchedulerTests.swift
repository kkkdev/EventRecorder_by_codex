import XCTest
@testable import EventRecorderCore

final class IntervalSnapshotSchedulerTests: XCTestCase {
    func testSchedulerFiresAtLeastTwice() throws {
        let expectation = expectation(description: "timer fired")
        expectation.expectedFulfillmentCount = 2

        let scheduler = IntervalSnapshotScheduler()
        defer { scheduler.stop() }

        try scheduler.start(intervalSeconds: 0.05, leewaySeconds: 0.0) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 0.4)
    }

    func testSchedulerRejectsNonPositiveInterval() {
        let scheduler = IntervalSnapshotScheduler()

        XCTAssertThrowsError(try scheduler.start(intervalSeconds: 0, handler: {})) { error in
            guard case .invalidInterval = error as? IntervalSnapshotSchedulerError else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }
    }
}
