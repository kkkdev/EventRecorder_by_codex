import Foundation
import XCTest
@testable import EventRecorderCore

final class TeamsAutomationLifecycleTests: XCTestCase {
    func testStartsExactlyOnceAfterGracePeriod() {
        let now = Date(timeIntervalSince1970: 100)
        var lifecycle = TeamsAutomationLifecycle()

        XCTAssertEqual(
            lifecycle.observe(
                candidateWindowID: 10,
                teamsIsRunning: true,
                visibleWindowIDs: [10],
                anotherCaptureIsRunning: false,
                now: now
            ),
            [.beginGracePeriod(windowID: 10, deadline: now.addingTimeInterval(5))]
        )
        XCTAssertEqual(
            lifecycle.observe(
                candidateWindowID: 10,
                teamsIsRunning: true,
                visibleWindowIDs: [10],
                anotherCaptureIsRunning: false,
                now: now.addingTimeInterval(5)
            ),
            [.startCapture(windowID: 10)]
        )
        XCTAssertTrue(
            lifecycle.observe(
                candidateWindowID: 10,
                teamsIsRunning: true,
                visibleWindowIDs: [10],
                anotherCaptureIsRunning: false,
                now: now.addingTimeInterval(6)
            ).isEmpty
        )
    }

    func testCancelSuppressesSameMeetingUntilItDisappears() {
        let now = Date(timeIntervalSince1970: 100)
        var lifecycle = TeamsAutomationLifecycle()
        _ = lifecycle.observe(
            candidateWindowID: 10,
            teamsIsRunning: true,
            visibleWindowIDs: [10],
            anotherCaptureIsRunning: false,
            now: now
        )

        XCTAssertEqual(lifecycle.cancelPendingStart(), .cancelGracePeriod)
        XCTAssertTrue(
            lifecycle.observe(
                candidateWindowID: 10,
                teamsIsRunning: true,
                visibleWindowIDs: [10],
                anotherCaptureIsRunning: false,
                now: now.addingTimeInterval(10)
            ).isEmpty
        )
        _ = lifecycle.observe(
            candidateWindowID: nil,
            teamsIsRunning: true,
            visibleWindowIDs: [10],
            anotherCaptureIsRunning: false,
            now: now.addingTimeInterval(11)
        )
        XCTAssertEqual(
            lifecycle.observe(
                candidateWindowID: 10,
                teamsIsRunning: true,
                visibleWindowIDs: [10],
                anotherCaptureIsRunning: false,
                now: now.addingTimeInterval(12)
            ).count,
            1
        )
    }

    func testStopsOnceWithSpecificReasonAfterMissingThreshold() {
        let cases: [(Bool, Set<UInt32>, CaptureStopReason)] = [
            (false, [], .teamsTerminated),
            (true, [], .targetWindowLost),
            (true, [10], .participantLeft)
        ]

        for (teamsIsRunning, visibleWindowIDs, expectedReason) in cases {
            var lifecycle = TeamsAutomationLifecycle(requiredMissingObservations: 3)
            lifecycle.markCaptureStarted(windowID: 10)
            for index in 0..<2 {
                XCTAssertTrue(
                    lifecycle.observe(
                        candidateWindowID: nil,
                        teamsIsRunning: teamsIsRunning,
                        visibleWindowIDs: visibleWindowIDs,
                        anotherCaptureIsRunning: false,
                        now: Date(timeIntervalSince1970: TimeInterval(index))
                    ).isEmpty
                )
            }
            XCTAssertEqual(
                lifecycle.observe(
                    candidateWindowID: nil,
                    teamsIsRunning: teamsIsRunning,
                    visibleWindowIDs: visibleWindowIDs,
                    anotherCaptureIsRunning: false,
                    now: Date(timeIntervalSince1970: 3)
                ),
                [.stopCapture(reason: expectedReason)]
            )
            XCTAssertTrue(
                lifecycle.observe(
                    candidateWindowID: nil,
                    teamsIsRunning: teamsIsRunning,
                    visibleWindowIDs: visibleWindowIDs,
                    anotherCaptureIsRunning: false,
                    now: Date(timeIntervalSince1970: 4)
                ).isEmpty
            )
        }
    }
}
