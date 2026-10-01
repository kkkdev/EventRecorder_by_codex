import Foundation

private enum VerificationError: Error {
    case failed(String)
}

@main
private enum TeamsAutomationVerifier {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 100)
        var lifecycle = TeamsAutomationLifecycle()
        let begin = lifecycle.observe(
            candidateWindowID: 10,
            teamsIsRunning: true,
            visibleWindowIDs: [10],
            anotherCaptureIsRunning: false,
            now: now
        )
        try expect(begin == [.beginGracePeriod(windowID: 10, deadline: now.addingTimeInterval(5))], "grace start")
        try expect(lifecycle.cancelPendingStart() == .cancelGracePeriod, "grace cancel")
        try expect(
            lifecycle.observe(
                candidateWindowID: 10,
                teamsIsRunning: true,
                visibleWindowIDs: [10],
                anotherCaptureIsRunning: false,
                now: now.addingTimeInterval(10)
            ).isEmpty,
            "cancelled meeting must remain suppressed"
        )

        var stopping = TeamsAutomationLifecycle(requiredMissingObservations: 3)
        stopping.markCaptureStarted(windowID: 20)
        for second in 1...2 {
            try expect(
                stopping.observe(
                    candidateWindowID: nil,
                    teamsIsRunning: true,
                    visibleWindowIDs: [],
                    anotherCaptureIsRunning: false,
                    now: now.addingTimeInterval(TimeInterval(second))
                ).isEmpty,
                "target loss grace"
            )
        }
        try expect(
            stopping.observe(
                candidateWindowID: nil,
                teamsIsRunning: true,
                visibleWindowIDs: [],
                anotherCaptureIsRunning: false,
                now: now.addingTimeInterval(3)
            ) == [.stopCapture(reason: .targetWindowLost)],
            "target loss stop reason"
        )

        print("teams automation verification passed")
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
