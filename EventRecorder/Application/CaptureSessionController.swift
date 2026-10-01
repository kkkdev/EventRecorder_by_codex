import Combine
import CoreMedia
import Foundation

public protocol CaptureSessionControllerProtocol: AnyObject {
    func prepare(includeOffscreen: Bool) async
    func start(settings: CaptureSettings) async
    func stop() async
}

public enum CaptureSessionControllerError: LocalizedError {
    case permissionDenied
    case invalidState(String)
    case sessionNotPrepared
    case noAudioCaptured
    case emptyAudioFile
    case silentAudioDetected(AudioDiagnostics)
    case targetUnavailableAfterFullscreen

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "画面収録権限がありません。システム設定で許可してください。"
        case .invalidState(let state):
            return "現在の状態では操作できません: \(state)"
        case .sessionNotPrepared:
            return "録画セッションが準備されていません。"
        case .noAudioCaptured:
            return "対象アプリの音声が取得できなかったため、MP3変換を中止しました。音声が再生されている状態で再実行してください。"
        case .emptyAudioFile:
            return "音声データが空のため、MP3変換を中止しました。"
        case .silentAudioDetected(let diagnostics):
            let peak = String(format: "%.1f", diagnostics.peakLevelDBFS)
            let rms = String(format: "%.1f", diagnostics.rmsLevelDBFS)
            return "音声ファイルは生成されましたが無音を検出しました（peak \(peak)dBFS / rms \(rms)dBFS）。" +
                "「Screen & System Audio Recording」権限を確認し、必要に応じて再付与して再実行してください。"
        case .targetUnavailableAfterFullscreen:
            return "全画面化などで対象ウィンドウが変化したため開始できません。対象を再選択して再実行してください。"
        }
    }
}

public final class CaptureSessionController: ObservableObject, CaptureSessionControllerProtocol {
    @Published public private(set) var state: CaptureState = .idle
    @Published public private(set) var availableTargets: [CaptureTarget] = []
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var lastWarningMessage: String?

    private let permissionManager: PermissionManaging
    private let screenCaptureService: ScreenCaptureServiceProtocol
    private let audioFileWriter: AudioFileWriting
    private let jpegFrameWriter: JpegFrameWriting
    private let ffmpegTranscoder: FFmpegTranscoderProtocol
    private let snapshotScheduler: IntervalSnapshotScheduler

    private let ioQueue = DispatchQueue(label: "event-recorder.io")
    private let sampleQueue = DispatchQueue(label: "event-recorder.sample")

    private var latestVideoSampleBuffer: CMSampleBuffer?
    private var activeSession: ActiveSession?
    private var finalizationGate = CaptureFinalizationGate()

    public init(
        permissionManager: PermissionManaging = PermissionManager(),
        screenCaptureService: ScreenCaptureServiceProtocol = ScreenCaptureService(),
        audioFileWriter: AudioFileWriting = AudioFileWriter(),
        jpegFrameWriter: JpegFrameWriting = JpegFrameWriter(),
        ffmpegTranscoder: FFmpegTranscoderProtocol = FFmpegTranscoder(),
        snapshotScheduler: IntervalSnapshotScheduler = IntervalSnapshotScheduler()
    ) {
        self.permissionManager = permissionManager
        self.screenCaptureService = screenCaptureService
        self.audioFileWriter = audioFileWriter
        self.jpegFrameWriter = jpegFrameWriter
        self.ffmpegTranscoder = ffmpegTranscoder
        self.snapshotScheduler = snapshotScheduler
    }

    public func prepare(includeOffscreen: Bool = false) async {
        do {
            let targets = try await screenCaptureService.availableCaptureTargets(includeOffscreen: includeOffscreen)
            DispatchQueue.main.async {
                self.availableTargets = targets
            }
        } catch {
            handleFailure(error)
        }
    }

    public func start(settings: CaptureSettings) async {
        guard !state.isRunning else {
            handleFailure(CaptureSessionControllerError.invalidState(state.statusText))
            return
        }

        DispatchQueue.main.async {
            self.state = .preparing
            self.lastErrorMessage = nil
            self.lastWarningMessage = nil
        }

        do {
            try FileManager.default.createDirectory(at: settings.outputDirectory, withIntermediateDirectories: true)
            let validated = try settings.validated()
            try await ensurePermission()
            let resolvedTarget = try await resolveTargetBeforeStart(validated.target)
            var resolvedSettings = validated
            resolvedSettings.target = resolvedTarget

            try await beginCapture(with: resolvedSettings)
            DispatchQueue.main.async {
                self.state = .capturing
            }
        } catch {
            try? await screenCaptureService.stopCapture()
            snapshotScheduler.stop()
            clearCaptureCallbacks()
            cleanupSessionDirectoryIfEmpty()
            ioQueue.sync {
                audioFileWriter.stop()
                activeSession = nil
            }
            sampleQueue.sync {
                latestVideoSampleBuffer = nil
            }
            handleFailure(error)
        }
    }

    public func stop() async {
        await stop(reason: .userStopped)
    }

    public func stop(reason: CaptureStopReason) async {
        guard state.canStop else {
            return
        }
        let shouldFinalize = ioQueue.sync {
            finalizationGate.begin()
        }
        guard shouldFinalize else {
            return
        }

        DispatchQueue.main.async {
            self.state = .stopping
        }
        ioQueue.sync {
            activeSession?.stopReason = reason
        }

        snapshotScheduler.stop()
        var stopError: Error?
        do {
            try await screenCaptureService.stopCapture()
        } catch {
            stopError = error
            recordStreamStopFailure(error)
        }
        clearCaptureCallbacks()

        do {
            let finalized = try finalizeSession(stopError: stopError)
            DispatchQueue.main.async {
                self.lastWarningMessage = finalized.warningMessage
                self.state = .completed(outputDirectory: finalized.sessionDirectory)
            }
        } catch {
            clearActiveSession()
            handleFailure(error)
        }
    }

    public func hasScreenRecordingPermission() -> Bool {
        permissionManager.preflightScreenCaptureAccess()
    }

    public func requestScreenRecordingPermission() -> Bool {
        permissionManager.requestScreenCaptureAccess()
    }

    public func resolveAvailableTarget(
        windowID: UInt32,
        processID: Int32
    ) async throws -> CaptureTarget? {
        try await screenCaptureService
            .availableCaptureTargets(includeOffscreen: true)
            .first { target in
                target.windowID == windowID && target.application.processID == processID
            }
    }

    public func openPermissionSettings() {
        permissionManager.openScreenRecordingSettings()
    }

    public func hasFFmpeg() -> Bool {
        ffmpegTranscoder.locateFFmpeg() != nil
    }

    private func ensurePermission() async throws {
        if permissionManager.preflightScreenCaptureAccess() {
            return
        }
        if permissionManager.requestScreenCaptureAccess() {
            return
        }
        throw CaptureSessionControllerError.permissionDenied
    }

    private func beginCapture(with settings: CaptureSettings) async throws {
        let startedAt = Date()
        let sessionID = Self.sessionDateFormatter.string(from: startedAt)

        let sessionDirectory = settings.outputDirectory.appendingPathComponent("session_\(sessionID)", isDirectory: true)
        let imageDirectory = sessionDirectory.appendingPathComponent("images", isDirectory: true)
        let tempAudioURL = sessionDirectory.appendingPathComponent("recording_tmp.caf")
        let finalAudioURL = sessionDirectory.appendingPathComponent("recording.mp3")

        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)

        ioQueue.sync {
            self.finalizationGate.reset()
            self.activeSession = ActiveSession(
                settings: settings,
                sessionID: sessionID,
                sessionDirectory: sessionDirectory,
                imageDirectory: imageDirectory,
                tempAudioURL: tempAudioURL,
                finalAudioURL: finalAudioURL,
                startedAt: startedAt,
                frames: [],
                frameIndex: 0,
                captureDiagnosticsAccumulator: CaptureDiagnosticsAccumulator(),
                firstAudioWriteError: nil,
                firstStreamError: nil,
                stopReason: nil
            )
        }

        try ioQueue.sync {
            try audioFileWriter.start(outputURL: tempAudioURL)
        }

        screenCaptureService.onVideoSampleBuffer = { [weak self] sampleBuffer in
            guard let self else { return }
            self.ioQueue.sync {
                guard var session = self.activeSession else { return }
                session.captureDiagnosticsAccumulator.recordVideoSampleBuffer()
                self.activeSession = session
            }
            guard let copied = Self.copy(sampleBuffer: sampleBuffer) else { return }
            self.sampleQueue.sync {
                self.latestVideoSampleBuffer = copied
            }
        }

        screenCaptureService.onAudioSampleBuffer = { [weak self] sampleBuffer in
            guard let self else { return }
            self.ioQueue.sync {
                guard var session = self.activeSession else { return }
                let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                session.captureDiagnosticsAccumulator.recordAudioSampleBuffer(
                    presentationTimeSeconds: pts
                )
                do {
                    try self.audioFileWriter.append(sampleBuffer: sampleBuffer)
                    session.captureDiagnosticsAccumulator.recordAudioWriteSuccess()
                } catch {
                    session.captureDiagnosticsAccumulator.recordAudioWriteFailure(error)
                    if session.firstAudioWriteError == nil {
                        session.firstAudioWriteError = error
                    }
                    let record = CaptureErrorRecord(error: error)
                    CaptureLog.audio.error(
                        "audio append failed domain=\(record.domain, privacy: .public) code=\(record.code, privacy: .public)"
                    )
                }
                self.activeSession = session
            }
        }

        screenCaptureService.onStreamError = { [weak self] error in
            guard let self else { return }
            let record = CaptureErrorRecord(error: error)
            CaptureLog.stream.error(
                "stream callback failed domain=\(record.domain, privacy: .public) code=\(record.code, privacy: .public)"
            )
            self.recordStreamStopFailure(error)
            Task {
                await self.stop(reason: .streamFailed)
            }
        }

        try await screenCaptureService.startCapture(
            target: settings.target,
            contentMode: settings.contentMode
        )
        CaptureLog.session.notice("session capture started")

        try snapshotScheduler.start(intervalSeconds: settings.intervalSeconds) { [weak self] in
            self?.captureSnapshotTick()
        }
    }

    private func resolveTargetBeforeStart(_ selectedTarget: CaptureTarget) async throws -> CaptureTarget {
        do {
            let latest = try await screenCaptureService.availableCaptureTargets(includeOffscreen: true)
            return try CaptureTargetResolver.resolve(selected: selectedTarget, latestTargets: latest)
        } catch CaptureTargetResolverError.unavailableAfterFullscreen {
            throw CaptureSessionControllerError.targetUnavailableAfterFullscreen
        }
    }

    private func cleanupSessionDirectoryIfEmpty() {
        ioQueue.sync {
            guard let session = activeSession else {
                return
            }
            let fm = FileManager.default
            let hasTempAudio = fm.fileExists(atPath: session.tempAudioURL.path)
            let imageFiles = (try? fm.contentsOfDirectory(
                at: session.imageDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            if !hasTempAudio && imageFiles.isEmpty {
                try? fm.removeItem(at: session.sessionDirectory)
            }
        }
    }

    private func captureSnapshotTick() {
        guard let sampleBuffer = sampleQueue.sync(execute: { latestVideoSampleBuffer }) else {
            return
        }

        ioQueue.async {
            guard var session = self.activeSession else {
                return
            }

            session.frameIndex += 1
            let fileName = String(format: "img_%06d.jpg", session.frameIndex)
            let outputURL = session.imageDirectory.appendingPathComponent(fileName)
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

            do {
                try self.jpegFrameWriter.write(
                    sampleBuffer: sampleBuffer,
                    to: outputURL,
                    quality: session.settings.jpegQuality
                )
                let normalizedPTS = pts.isFinite ? pts : 0
                session.frames.append(
                    .init(fileName: fileName, capturePTSSeconds: normalizedPTS, savedAt: Date())
                )
                self.activeSession = session
            } catch {
                self.handleFailure(error)
            }
        }
    }

    private func finalizeSession(stopError: Error?) throws -> FinalizedSession {
        let (session, audioDiagnostics, captureDiagnostics) = try ioQueue.sync {
            () throws -> (ActiveSession, AudioDiagnostics, CaptureDiagnostics) in
            guard let activeSession else {
                throw CaptureSessionControllerError.sessionNotPrepared
            }
            audioFileWriter.stop()
            return (
                activeSession,
                audioFileWriter.diagnosticsSnapshot(),
                activeSession.captureDiagnosticsAccumulator.makeDiagnostics()
            )
        }

        if let captureError = CaptureFinalizationFailureResolver.preferredError(
            audioWriteError: session.firstAudioWriteError,
            streamStopError: stopError ?? session.firstStreamError
        ) {
            writeFailureManifestBestEffort(
                session: session,
                audioDiagnostics: audioDiagnostics,
                captureDiagnostics: captureDiagnostics
            )
            throw captureError
        }

        let finalizationPlan = CaptureCompletionResolver.makeFinalizationPlan(
            captureDiagnostics: captureDiagnostics,
            audioDiagnostics: audioDiagnostics,
            audioFileName: session.finalAudioURL.lastPathComponent
        )
        let completionStatus = finalizationPlan.completionStatus

        if !finalizationPlan.shouldTranscodeAudio {
            let manifest = makeManifest(
                session: session,
                audioFileName: finalizationPlan.audioFileName,
                audioDiagnostics: audioDiagnostics,
                captureDiagnostics: captureDiagnostics,
                completionStatus: completionStatus
            )
            try writeFinalManifest(manifest, to: session.sessionDirectory)
            logFinalization(status: completionStatus, diagnostics: captureDiagnostics)
            clearActiveSession()
            return FinalizedSession(
                sessionDirectory: session.sessionDirectory,
                warningMessage: "音声サンプルを取得できなかったため、MP3なしで画像と診断情報を保存しました。"
            )
        }

        do {
            try AudioInputPreflight.validate(tempAudioURL: session.tempAudioURL)
        } catch {
            let record = CaptureErrorRecord(error: error)
            CaptureLog.audio.error(
                "audio input validation failed domain=\(record.domain, privacy: .public) code=\(record.code, privacy: .public)"
            )
            writeFailureManifestBestEffort(
                session: session,
                audioDiagnostics: audioDiagnostics,
                captureDiagnostics: captureDiagnostics
            )
            throw error
        }

        do {
            try ffmpegTranscoder.transcodeToMp3(
                inputURL: session.tempAudioURL,
                outputURL: session.finalAudioURL,
                bitrateKbps: session.settings.audioBitrateKbps
            )
        } catch {
            let record = CaptureErrorRecord(error: error)
            CaptureLog.audio.error(
                "audio conversion failed domain=\(record.domain, privacy: .public) code=\(record.code, privacy: .public)"
            )
            writeFailureManifestBestEffort(
                session: session,
                audioDiagnostics: audioDiagnostics,
                captureDiagnostics: captureDiagnostics
            )
            throw error
        }

        let manifest = makeManifest(
            session: session,
            audioFileName: finalizationPlan.audioFileName,
            audioDiagnostics: audioDiagnostics,
            captureDiagnostics: captureDiagnostics,
            completionStatus: completionStatus
        )

        try writeFinalManifest(manifest, to: session.sessionDirectory)
        logFinalization(status: completionStatus, diagnostics: captureDiagnostics)
        clearActiveSession()

        var warningMessage: String?
        if completionStatus == .completedWithWarnings {
            let peak = String(format: "%.1f", audioDiagnostics.peakLevelDBFS)
            let rms = String(format: "%.1f", audioDiagnostics.rmsLevelDBFS)
            warningMessage = "音声サンプルは取得できましたが無音を検出しました" +
                "（peak \(peak)dBFS / rms \(rms)dBFS）。MP3と診断情報を保存しました。"
        }

        return FinalizedSession(
            sessionDirectory: session.sessionDirectory,
            warningMessage: warningMessage
        )
    }

    private func makeManifest(
        session: ActiveSession,
        audioFileName: String?,
        audioDiagnostics: AudioDiagnostics,
        captureDiagnostics: CaptureDiagnostics,
        completionStatus: CaptureCompletionStatus?
    ) -> CaptureManifest {
        let persistedTarget: CaptureTarget
        if session.settings.trigger == .teamsAutomatic {
            persistedTarget = CaptureTarget(
                windowID: session.settings.target.windowID,
                displayID: session.settings.target.displayID,
                windowTitle: "",
                application: session.settings.target.application
            )
        } else {
            persistedTarget = session.settings.target
        }

        return CaptureManifest(
            sessionID: session.sessionID,
            captureTarget: persistedTarget,
            intervalSeconds: session.settings.intervalSeconds,
            startedAt: session.startedAt,
            endedAt: Date(),
            audioFileName: audioFileName,
            audioDiagnostics: audioDiagnostics,
            imageDirectoryName: session.imageDirectory.lastPathComponent,
            frames: session.frames,
            completionStatus: completionStatus,
            captureDiagnostics: captureDiagnostics,
            trigger: session.settings.trigger,
            captureScope: session.settings.contentMode == .window ? .window : .display,
            audioScope: session.settings.contentMode == .window ? .application : .display,
            stopReason: session.stopReason,
            segmentGroupID: session.settings.segmentGroupID,
            microphoneIncluded: false,
            presenceEvidenceVersion: session.settings.presenceEvidenceVersion
        )
    }

    private func writeFinalManifest(_ manifest: CaptureManifest, to directory: URL) throws {
        do {
            _ = try manifest.write(to: directory)
        } catch {
            let record = CaptureErrorRecord(error: error)
            CaptureLog.session.error(
                "manifest write failed domain=\(record.domain, privacy: .public) code=\(record.code, privacy: .public)"
            )
            throw error
        }
    }

    private func writeFailureManifestBestEffort(
        session: ActiveSession,
        audioDiagnostics: AudioDiagnostics,
        captureDiagnostics: CaptureDiagnostics
    ) {
        let manifest = makeManifest(
            session: session,
            audioFileName: nil,
            audioDiagnostics: audioDiagnostics,
            captureDiagnostics: captureDiagnostics,
            completionStatus: nil
        )
        do {
            _ = try manifest.write(to: session.sessionDirectory)
        } catch {
            let record = CaptureErrorRecord(error: error)
            CaptureLog.session.error(
                "failure manifest write failed domain=\(record.domain, privacy: .public) code=\(record.code, privacy: .public)"
            )
        }
    }

    private func logFinalization(
        status: CaptureCompletionStatus,
        diagnostics: CaptureDiagnostics
    ) {
        CaptureLog.session.notice(
            "session finalized status=\(status.rawValue, privacy: .public) videoSamples=\(diagnostics.videoSampleBufferCount, privacy: .public) audioSamples=\(diagnostics.audioSampleBufferCount, privacy: .public) audioWrites=\(diagnostics.audioWriteSuccessCount, privacy: .public) audioWriteFailures=\(diagnostics.audioWriteFailureCount, privacy: .public)"
        )
    }

    private func recordStreamStopFailure(_ error: Error) {
        ioQueue.sync {
            guard var session = activeSession else {
                return
            }
            session.captureDiagnosticsAccumulator.recordStreamStopFailure(error)
            if session.firstStreamError == nil {
                session.firstStreamError = error
            }
            activeSession = session
        }
    }

    private func clearCaptureCallbacks() {
        screenCaptureService.onVideoSampleBuffer = nil
        screenCaptureService.onAudioSampleBuffer = nil
        screenCaptureService.onStreamError = nil
    }

    private func clearActiveSession() {
        ioQueue.sync {
            activeSession = nil
        }
        sampleQueue.sync {
            latestVideoSampleBuffer = nil
        }
    }

    private func handleFailure(_ error: Error) {
        let record = CaptureErrorRecord(error: error)
        CaptureLog.session.error(
            "session failed domain=\(record.domain, privacy: .public) code=\(record.code, privacy: .public)"
        )
        DispatchQueue.main.async {
            self.lastErrorMessage = error.localizedDescription
            self.lastWarningMessage = nil
            self.state = .failed(error)
        }
    }

    private static func copy(sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        var copied: CMSampleBuffer?
        let status = CMSampleBufferCreateCopy(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleBufferOut: &copied
        )
        guard status == noErr else {
            return nil
        }
        return copied
    }

    private struct ActiveSession {
        let settings: CaptureSettings
        let sessionID: String
        let sessionDirectory: URL
        let imageDirectory: URL
        let tempAudioURL: URL
        let finalAudioURL: URL
        let startedAt: Date
        var frames: [CaptureManifest.FrameRecord]
        var frameIndex: Int
        var captureDiagnosticsAccumulator: CaptureDiagnosticsAccumulator
        var firstAudioWriteError: Error?
        var firstStreamError: Error?
        var stopReason: CaptureStopReason?
    }

    private struct FinalizedSession {
        let sessionDirectory: URL
        let warningMessage: String?
    }

    private static let sessionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
