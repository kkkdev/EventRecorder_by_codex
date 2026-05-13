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
            await screenCaptureService.stopCapture()
            snapshotScheduler.stop()
            cleanupSessionDirectoryIfEmpty()
            ioQueue.sync {
                audioFileWriter.stop()
                activeSession = nil
            }
            handleFailure(error)
        }
    }

    public func stop() async {
        guard state.isRunning || isCapturingState else {
            return
        }

        DispatchQueue.main.async {
            self.state = .stopping
        }

        snapshotScheduler.stop()
        await screenCaptureService.stopCapture()
        screenCaptureService.onVideoSampleBuffer = nil
        screenCaptureService.onAudioSampleBuffer = nil

        do {
            let finalized = try finalizeSession()
            DispatchQueue.main.async {
                self.state = .completed(outputDirectory: finalized.sessionDirectory)
            }
        } catch {
            handleFailure(error)
        }
    }

    public func hasScreenRecordingPermission() -> Bool {
        permissionManager.preflightScreenCaptureAccess()
    }

    public func requestScreenRecordingPermission() -> Bool {
        permissionManager.requestScreenCaptureAccess()
    }

    public func openPermissionSettings() {
        permissionManager.openScreenRecordingSettings()
    }

    public func hasFFmpeg() -> Bool {
        ffmpegTranscoder.locateFFmpeg() != nil
    }

    private var isCapturingState: Bool {
        if case .capturing = state {
            return true
        }
        return false
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
            self.activeSession = ActiveSession(
                settings: settings,
                sessionID: sessionID,
                sessionDirectory: sessionDirectory,
                imageDirectory: imageDirectory,
                tempAudioURL: tempAudioURL,
                finalAudioURL: finalAudioURL,
                startedAt: startedAt,
                frames: [],
                frameIndex: 0
            )
        }

        try ioQueue.sync {
            try audioFileWriter.start(outputURL: tempAudioURL)
        }

        screenCaptureService.onVideoSampleBuffer = { [weak self] sampleBuffer in
            guard let self else { return }
            guard let copied = Self.copy(sampleBuffer: sampleBuffer) else { return }
            self.sampleQueue.sync {
                self.latestVideoSampleBuffer = copied
            }
        }

        screenCaptureService.onAudioSampleBuffer = { [weak self] sampleBuffer in
            guard let self else { return }
            self.ioQueue.sync {
                do {
                    try self.audioFileWriter.append(sampleBuffer: sampleBuffer)
                } catch {
                    self.handleFailure(error)
                }
            }
        }

        try await screenCaptureService.startCapture(target: settings.target)

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

    private func finalizeSession() throws -> ActiveSession {
        let (session, audioDiagnostics) = try ioQueue.sync { () throws -> (ActiveSession, AudioDiagnostics) in
            guard let activeSession else {
                throw CaptureSessionControllerError.sessionNotPrepared
            }
            audioFileWriter.stop()
            return (activeSession, audioFileWriter.diagnosticsSnapshot())
        }

        do {
            try AudioInputPreflight.validate(tempAudioURL: session.tempAudioURL)
        } catch AudioInputPreflightError.fileMissing {
            throw CaptureSessionControllerError.noAudioCaptured
        } catch AudioInputPreflightError.fileEmpty {
            throw CaptureSessionControllerError.emptyAudioFile
        }

        do {
            try ffmpegTranscoder.transcodeToMp3(
                inputURL: session.tempAudioURL,
                outputURL: session.finalAudioURL,
                bitrateKbps: session.settings.audioBitrateKbps
            )
        } catch {
            throw error
        }

        let endedAt = Date()
        let manifest = CaptureManifest(
            sessionID: session.sessionID,
            captureTarget: session.settings.target,
            intervalSeconds: session.settings.intervalSeconds,
            startedAt: session.startedAt,
            endedAt: endedAt,
            audioFileName: session.finalAudioURL.lastPathComponent,
            audioDiagnostics: audioDiagnostics,
            imageDirectoryName: session.imageDirectory.lastPathComponent,
            frames: session.frames
        )

        _ = try manifest.write(to: session.sessionDirectory)

        ioQueue.sync {
            self.activeSession = nil
            self.latestVideoSampleBuffer = nil
        }

        if audioDiagnostics.isSilent {
            throw CaptureSessionControllerError.silentAudioDetected(audioDiagnostics)
        }

        return session
    }

    private func handleFailure(_ error: Error) {
        DispatchQueue.main.async {
            self.lastErrorMessage = error.localizedDescription
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
    }

    private static let sessionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
