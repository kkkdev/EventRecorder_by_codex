import Combine
import Foundation

public struct TeamsAutomationCapturePreferences: Equatable {
    public let intervalSeconds: Double
    public let jpegQuality: Double
    public let outputDirectory: URL
    public let audioBitrateKbps: Int

    public init(
        intervalSeconds: Double,
        jpegQuality: Double,
        outputDirectory: URL,
        audioBitrateKbps: Int
    ) {
        self.intervalSeconds = intervalSeconds
        self.jpegQuality = jpegQuality
        self.outputDirectory = outputDirectory
        self.audioBitrateKbps = audioBitrateKbps
    }
}

@MainActor
public final class TeamsAutomationController: ObservableObject {
    @Published public private(set) var isMonitoring = false
    @Published public private(set) var statusText = "停止中"
    @Published public private(set) var pendingStartSeconds: Int?
    @Published public private(set) var message: String?

    public static let presenceEvidenceVersion = "teams-ax-v1"

    private let captureController: CaptureSessionController
    private let snapshotProvider: TeamsAccessibilitySnapshotProviding
    private let permissionManager: AccessibilityPermissionManaging
    private let notifier: TeamsAutomationNotifying
    private let pollIntervalNanoseconds: UInt64

    private var lifecycle = TeamsAutomationLifecycle()
    private var stabilizer = TeamsMeetingPresenceStabilizer()
    private var preferences: TeamsAutomationCapturePreferences?
    private var pollTask: Task<Void, Never>?

    public init(
        captureController: CaptureSessionController,
        snapshotProvider: TeamsAccessibilitySnapshotProviding? = nil,
        permissionManager: AccessibilityPermissionManaging = AccessibilityPermissionManager(),
        notifier: TeamsAutomationNotifying = TeamsAutomationNotifier(),
        pollIntervalNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.captureController = captureController
        self.permissionManager = permissionManager
        self.snapshotProvider = snapshotProvider
            ?? TeamsAccessibilitySnapshotProvider(permissionManager: permissionManager)
        self.notifier = notifier
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    deinit {
        pollTask?.cancel()
    }

    public func hasAccessibilityPermission() -> Bool {
        permissionManager.hasPermission()
    }

    @discardableResult
    public func requestAccessibilityPermission() -> Bool {
        permissionManager.requestPermission()
    }

    public func openAccessibilitySettings() {
        permissionManager.openAccessibilitySettings()
    }

    public func startMonitoring(preferences: TeamsAutomationCapturePreferences) {
        guard !isMonitoring else {
            self.preferences = preferences
            return
        }
        guard permissionManager.hasPermission() else {
            _ = permissionManager.requestPermission()
            statusText = "Accessibility権限が必要です"
            message = "システム設定でEvent RecorderのAccessibility権限を許可してください。"
            return
        }

        self.preferences = preferences
        message = nil
        isMonitoring = true
        statusText = "Teams会議を監視中"
        CaptureLog.teams.notice("teams monitoring started")

        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce()
                do {
                    try await Task.sleep(nanoseconds: self.pollIntervalNanoseconds)
                } catch {
                    break
                }
            }
        }
    }

    public func stopMonitoring() async {
        pollTask?.cancel()
        pollTask = nil
        if lifecycle.activeWindowID != nil {
            await captureController.stop(reason: .userStopped)
        }
        _ = lifecycle.reset()
        stabilizer.reset()
        pendingStartSeconds = nil
        isMonitoring = false
        statusText = "停止中"
        CaptureLog.teams.notice("teams monitoring stopped")
    }

    public func cancelPendingStart() {
        guard lifecycle.cancelPendingStart() != nil else {
            return
        }
        pendingStartSeconds = nil
        statusText = "この会議の自動録画を取消済み"
        CaptureLog.teams.notice("pending automatic capture cancelled")
    }

    public func stopCaptureByUser() async {
        if lifecycle.activeWindowID != nil {
            await captureController.stop(reason: .userStopped)
            lifecycle.markCaptureStopped(suppressCurrentMeeting: true)
            statusText = isMonitoring ? "この会議の自動録画を停止済み" : "停止中"
            return
        }
        await captureController.stop(reason: .userStopped)
    }

    public func handleSystemWillSleep() async {
        guard captureController.state.canStop else {
            return
        }
        await captureController.stop(reason: .systemSleep)
        lifecycle.markCaptureStopped(suppressCurrentMeeting: true)
        pendingStartSeconds = nil
        statusText = isMonitoring ? "スリープのため録画を停止" : "停止中"
    }

    private func pollOnce() async {
        guard isMonitoring else {
            return
        }

        if lifecycle.activeWindowID != nil, !captureController.state.isRunning {
            lifecycle.markCaptureStopped(suppressCurrentMeeting: true)
            statusText = "自動録画が終了しました。Teams会議を監視中"
        }

        do {
            let batch = try await snapshotProvider.snapshot()
            let rawCandidate = TeamsMeetingPresenceDetector.uniqueCandidate(in: batch.windows)
            let stableCandidate = stabilizer.observe(rawCandidate)
            let actions = lifecycle.observe(
                candidateWindowID: stableCandidate?.windowID,
                teamsIsRunning: batch.teamsIsRunning,
                visibleWindowIDs: Set(batch.windows.map(\.windowID)),
                anotherCaptureIsRunning: captureController.state.isRunning
                    && lifecycle.activeWindowID == nil,
                now: Date()
            )
            for action in actions {
                await apply(action, evidence: stableCandidate)
            }
            updateCountdown()
        } catch TeamsAccessibilitySnapshotError.permissionDenied {
            message = "Accessibility権限がありません。監視を停止しました。"
            stopPollingAfterFailure(status: "Accessibility権限が必要です")
        } catch {
            let record = CaptureErrorRecord(error: error)
            CaptureLog.teams.error(
                "teams monitoring failed domain=\(record.domain, privacy: .public) code=\(record.code, privacy: .public)"
            )
            message = "Teams会議の監視に失敗しました。"
            stopPollingAfterFailure(status: "監視エラー")
        }
    }

    private func apply(
        _ action: TeamsAutomationAction,
        evidence: TeamsMeetingPresenceEvidence?
    ) async {
        switch action {
        case .beginGracePeriod(_, let deadline):
            pendingStartSeconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
            statusText = "録画開始待ち（取消可能）"
            notifier.notifyCaptureWillStart(gracePeriodSeconds: 5)
            CaptureLog.teams.notice("automatic capture grace period started")
        case .cancelGracePeriod:
            pendingStartSeconds = nil
            statusText = "Teams会議を監視中"
        case .startCapture(let windowID):
            pendingStartSeconds = nil
            guard let preferences,
                  let processID = evidence?.processID,
                  let target = try? await captureController.resolveAvailableTarget(
                      windowID: windowID,
                      processID: processID
                  ) else {
                lifecycle.markCaptureStartFailed(windowID: windowID)
                statusText = "対象ウィンドウを特定できません"
                message = "Teams会議ウィンドウを一意に特定できなかったため録画を開始しませんでした。"
                return
            }

            let segmentGroupID = UUID().uuidString.lowercased()
            lifecycle.markCaptureStarted(windowID: windowID)
            statusText = "Teams会議を自動録画中"
            CaptureLog.teams.notice("automatic capture starting")
            await captureController.start(
                settings: CaptureSettings(
                    target: target,
                    intervalSeconds: preferences.intervalSeconds,
                    jpegQuality: preferences.jpegQuality,
                    outputDirectory: preferences.outputDirectory,
                    audioBitrateKbps: preferences.audioBitrateKbps,
                    contentMode: .window,
                    trigger: .teamsAutomatic,
                    segmentGroupID: segmentGroupID,
                    presenceEvidenceVersion: Self.presenceEvidenceVersion
                )
            )
        case .stopCapture(let reason):
            CaptureLog.teams.notice("automatic capture stopping reason=\(reason.rawValue, privacy: .public)")
            await captureController.stop(reason: reason)
            lifecycle.markCaptureStopped()
            statusText = "Teams会議を監視中"
        }
    }

    private func updateCountdown() {
        guard let deadline = lifecycle.pendingDeadline else {
            return
        }
        pendingStartSeconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
    }

    private func stopPollingAfterFailure(status: String) {
        pollTask?.cancel()
        pollTask = nil
        _ = lifecycle.reset()
        stabilizer.reset()
        pendingStartSeconds = nil
        isMonitoring = false
        statusText = status
    }
}
