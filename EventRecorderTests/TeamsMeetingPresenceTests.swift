import XCTest
@testable import EventRecorderCore

final class TeamsMeetingPresenceTests: XCTestCase {
    func testTeamsProcessWithoutMeetingControlsIsNotCandidate() {
        let snapshot = makeSnapshot(elements: [
            .init(role: "AXButton", label: "予定表"),
            .init(role: "AXButton", label: "チャット")
        ])

        XCTAssertFalse(TeamsMeetingPresenceDetector.evidence(for: snapshot).isConfirmedCandidate)
    }

    func testPrejoinControlsAreNotCandidateWithoutLeaveControl() {
        let snapshot = makeSnapshot(elements: [
            .init(role: "AXButton", label: "マイク"),
            .init(role: "AXButton", label: "カメラ"),
            .init(role: "AXButton", label: "今すぐ参加")
        ])

        XCTAssertFalse(TeamsMeetingPresenceDetector.evidence(for: snapshot).isConfirmedCandidate)
    }

    func testJapaneseMeetingToolbarIsCandidate() {
        let snapshot = makeSnapshot(elements: [
            .init(role: "AXButton", label: "マイクをミュート"),
            .init(role: "AXButton", label: "カメラをオフにする"),
            .init(role: "AXButton", label: "会議から退出")
        ])

        let evidence = TeamsMeetingPresenceDetector.evidence(for: snapshot)
        XCTAssertTrue(evidence.isConfirmedCandidate)
        XCTAssertEqual(evidence.supportingControlKinds, [.microphone, .camera])
    }

    func testEnglishCallToolbarIsCandidate() {
        let snapshot = makeSnapshot(elements: [
            .init(role: "AXButton", label: "Mute microphone"),
            .init(role: "AXButton", label: "Show participants"),
            .init(role: "AXButton", label: "Hang up")
        ])

        XCTAssertTrue(TeamsMeetingPresenceDetector.evidence(for: snapshot).isConfirmedCandidate)
    }

    func testNonTeamsApplicationIsRejected() {
        let snapshot = makeSnapshot(
            bundleIdentifier: "com.example.other",
            elements: [
                .init(role: "AXButton", label: "Mute microphone"),
                .init(role: "AXButton", label: "Show participants"),
                .init(role: "AXButton", label: "Hang up")
            ]
        )

        XCTAssertFalse(TeamsMeetingPresenceDetector.evidence(for: snapshot).isConfirmedCandidate)
    }

    func testAmbiguousMeetingWindowsAreRejected() {
        let first = makeSnapshot(windowID: 10, elements: meetingControls)
        let second = makeSnapshot(windowID: 20, elements: meetingControls)

        XCTAssertNil(TeamsMeetingPresenceDetector.uniqueCandidate(in: [first, second]))
    }

    func testStabilizerRequiresConsecutiveSameWindow() {
        var stabilizer = TeamsMeetingPresenceStabilizer(requiredConsecutiveObservations: 2)
        let first = TeamsMeetingPresenceDetector.evidence(
            for: makeSnapshot(windowID: 10, elements: meetingControls)
        )
        let other = TeamsMeetingPresenceDetector.evidence(
            for: makeSnapshot(windowID: 20, elements: meetingControls)
        )

        XCTAssertNil(stabilizer.observe(first))
        XCTAssertNil(stabilizer.observe(other))
        XCTAssertEqual(stabilizer.observe(other)?.windowID, 20)
        XCTAssertNil(stabilizer.observe(nil))
        XCTAssertNil(stabilizer.observe(other))
    }

    private var meetingControls: [TeamsAccessibilityElementSnapshot] {
        [
            .init(role: "AXButton", label: "Mute microphone"),
            .init(role: "AXButton", label: "Show participants"),
            .init(role: "AXButton", label: "Hang up")
        ]
    }

    private func makeSnapshot(
        windowID: UInt32 = 10,
        bundleIdentifier: String = TeamsMeetingPresenceDetector.teamsBundleIdentifier,
        elements: [TeamsAccessibilityElementSnapshot]
    ) -> TeamsAccessibilityWindowSnapshot {
        TeamsAccessibilityWindowSnapshot(
            windowID: windowID,
            processID: 100,
            bundleIdentifier: bundleIdentifier,
            elements: elements
        )
    }
}
