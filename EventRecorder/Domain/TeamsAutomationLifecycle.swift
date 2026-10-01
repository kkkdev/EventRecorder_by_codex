import Foundation

public enum TeamsAutomationAction: Equatable {
    case beginGracePeriod(windowID: UInt32, deadline: Date)
    case cancelGracePeriod
    case startCapture(windowID: UInt32)
    case stopCapture(reason: CaptureStopReason)
}

public struct TeamsAutomationLifecycle: Equatable {
    public let gracePeriodSeconds: TimeInterval
    public let requiredMissingObservations: Int

    public private(set) var pendingWindowID: UInt32?
    public private(set) var pendingDeadline: Date?
    public private(set) var activeWindowID: UInt32?

    private var suppressedWindowID: UInt32?
    private var missingObservationCount = 0
    private var startRequestedWindowID: UInt32?
    private var stopRequested = false

    public init(
        gracePeriodSeconds: TimeInterval = 5,
        requiredMissingObservations: Int = 3
    ) {
        self.gracePeriodSeconds = max(0, gracePeriodSeconds)
        self.requiredMissingObservations = max(1, requiredMissingObservations)
    }

    public mutating func observe(
        candidateWindowID: UInt32?,
        teamsIsRunning: Bool,
        visibleWindowIDs: Set<UInt32>,
        anotherCaptureIsRunning: Bool,
        now: Date
    ) -> [TeamsAutomationAction] {
        if let activeWindowID {
            return observeActiveCapture(
                windowID: activeWindowID,
                candidateWindowID: candidateWindowID,
                teamsIsRunning: teamsIsRunning,
                visibleWindowIDs: visibleWindowIDs
            )
        }

        if anotherCaptureIsRunning {
            return clearPendingIfNeeded()
        }

        if let startRequestedWindowID {
            if candidateWindowID != startRequestedWindowID {
                self.startRequestedWindowID = nil
            }
            return []
        }

        if let suppressedWindowID {
            if candidateWindowID == suppressedWindowID {
                return []
            }
            self.suppressedWindowID = nil
        }

        if let pendingWindowID, let pendingDeadline {
            guard candidateWindowID == pendingWindowID else {
                self.pendingWindowID = nil
                self.pendingDeadline = nil
                var actions: [TeamsAutomationAction] = [.cancelGracePeriod]
                actions.append(contentsOf: beginPendingIfPossible(candidateWindowID: candidateWindowID, now: now))
                return actions
            }

            guard now >= pendingDeadline else {
                return []
            }
            self.pendingWindowID = nil
            self.pendingDeadline = nil
            startRequestedWindowID = pendingWindowID
            return [.startCapture(windowID: pendingWindowID)]
        }

        return beginPendingIfPossible(candidateWindowID: candidateWindowID, now: now)
    }

    public mutating func cancelPendingStart() -> TeamsAutomationAction? {
        guard let pendingWindowID else {
            return nil
        }
        suppressedWindowID = pendingWindowID
        self.pendingWindowID = nil
        pendingDeadline = nil
        return .cancelGracePeriod
    }

    public mutating func markCaptureStarted(windowID: UInt32) {
        activeWindowID = windowID
        startRequestedWindowID = nil
        missingObservationCount = 0
        stopRequested = false
    }

    public mutating func markCaptureStartFailed(windowID: UInt32) {
        if startRequestedWindowID == windowID {
            startRequestedWindowID = nil
            suppressedWindowID = windowID
        }
    }

    public mutating func markCaptureStopped(suppressCurrentMeeting: Bool = false) {
        if suppressCurrentMeeting, let activeWindowID {
            suppressedWindowID = activeWindowID
        }
        activeWindowID = nil
        startRequestedWindowID = nil
        missingObservationCount = 0
        stopRequested = false
    }

    public mutating func reset() -> TeamsAutomationAction? {
        let hadPendingStart = pendingWindowID != nil
        pendingWindowID = nil
        pendingDeadline = nil
        activeWindowID = nil
        suppressedWindowID = nil
        missingObservationCount = 0
        startRequestedWindowID = nil
        stopRequested = false
        return hadPendingStart ? .cancelGracePeriod : nil
    }

    private mutating func beginPendingIfPossible(
        candidateWindowID: UInt32?,
        now: Date
    ) -> [TeamsAutomationAction] {
        guard let candidateWindowID else {
            return []
        }
        let deadline = now.addingTimeInterval(gracePeriodSeconds)
        pendingWindowID = candidateWindowID
        pendingDeadline = deadline
        return [.beginGracePeriod(windowID: candidateWindowID, deadline: deadline)]
    }

    private mutating func clearPendingIfNeeded() -> [TeamsAutomationAction] {
        guard pendingWindowID != nil else {
            return []
        }
        pendingWindowID = nil
        pendingDeadline = nil
        return [.cancelGracePeriod]
    }

    private mutating func observeActiveCapture(
        windowID: UInt32,
        candidateWindowID: UInt32?,
        teamsIsRunning: Bool,
        visibleWindowIDs: Set<UInt32>
    ) -> [TeamsAutomationAction] {
        guard !stopRequested else {
            return []
        }
        guard teamsIsRunning, candidateWindowID == windowID else {
            missingObservationCount += 1
            guard missingObservationCount >= requiredMissingObservations else {
                return []
            }
            stopRequested = true
            let reason: CaptureStopReason
            if !teamsIsRunning {
                reason = .teamsTerminated
            } else if !visibleWindowIDs.contains(windowID) {
                reason = .targetWindowLost
            } else {
                reason = .participantLeft
            }
            return [.stopCapture(reason: reason)]
        }
        missingObservationCount = 0
        return []
    }
}
