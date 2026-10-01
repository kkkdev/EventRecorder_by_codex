import Foundation

private enum VerificationError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
private enum TeamsPresenceVerifier {
    static func main() throws {
        let prejoin = snapshot(elements: ["マイク", "カメラ", "今すぐ参加"])
        try expect(
            !TeamsMeetingPresenceDetector.evidence(for: prejoin).isConfirmedCandidate,
            "prejoin must not be treated as joined"
        )

        let joined = snapshot(elements: ["マイクをミュート", "参加者", "会議から退出"])
        let joinedEvidence = TeamsMeetingPresenceDetector.evidence(for: joined)
        try expect(joinedEvidence.isConfirmedCandidate, "joined meeting must be detected")

        var stabilizer = TeamsMeetingPresenceStabilizer(requiredConsecutiveObservations: 2)
        try expect(stabilizer.observe(joinedEvidence) == nil, "first observation must be pending")
        try expect(
            stabilizer.observe(joinedEvidence)?.windowID == joined.windowID,
            "second observation must confirm the same window"
        )

        let ambiguous = TeamsMeetingPresenceDetector.uniqueCandidate(
            in: [joined, snapshot(windowID: 20, elements: ["Mute", "People", "Hang up"])]
        )
        try expect(ambiguous == nil, "ambiguous meeting windows must be rejected")

        print("teams presence verification passed")
    }

    private static func snapshot(
        windowID: UInt32 = 10,
        elements: [String]
    ) -> TeamsAccessibilityWindowSnapshot {
        TeamsAccessibilityWindowSnapshot(
            windowID: windowID,
            processID: 100,
            bundleIdentifier: TeamsMeetingPresenceDetector.teamsBundleIdentifier,
            elements: elements.map {
                TeamsAccessibilityElementSnapshot(role: "AXButton", label: $0)
            }
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw VerificationError.failed(message)
        }
    }
}
