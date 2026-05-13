import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

public protocol ScreenCaptureServiceProtocol: AnyObject {
    var onVideoSampleBuffer: ((CMSampleBuffer) -> Void)? { get set }
    var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)? { get set }

    func availableCaptureTargets(includeOffscreen: Bool) async throws -> [CaptureTarget]
    func startCapture(target: CaptureTarget) async throws
    func stopCapture() async
}

public enum ScreenCaptureServiceError: LocalizedError {
    case targetWindowNotFound(UInt32)
    case displayNotFound(UInt32)
    case targetApplicationNotFound(Int32)
    case targetWithoutOwningApplication(UInt32)

    public var errorDescription: String? {
        switch self {
        case .targetWindowNotFound(let id):
            return "指定したウィンドウが見つかりません: \(id)"
        case .displayNotFound(let id):
            return "対象ディスプレイが見つかりません: \(id)"
        case .targetApplicationNotFound(let pid):
            return "対象アプリが見つかりません: pid=\(pid)"
        case .targetWithoutOwningApplication(let id):
            return "対象ウィンドウのアプリ情報が取得できません: \(id)"
        }
    }
}

public final class ScreenCaptureService: NSObject, ScreenCaptureServiceProtocol {
    public var onVideoSampleBuffer: ((CMSampleBuffer) -> Void)?
    public var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)?

    private let videoQueue = DispatchQueue(label: "event-recorder.video.sample")
    private let audioQueue = DispatchQueue(label: "event-recorder.audio.sample")

    private var stream: SCStream?

    public override init() {
        super.init()
    }

    public func availableCaptureTargets(includeOffscreen: Bool = false) async throws -> [CaptureTarget] {
        let content = try await loadShareableContent(onScreenWindowsOnly: !includeOffscreen)

        let targets = content.windows.compactMap { window -> CaptureTarget? in
            if !includeOffscreen && !window.isOnScreen {
                return nil
            }
            guard let app = window.owningApplication else {
                return nil
            }
            guard let display = resolveDisplay(for: window.frame, displays: content.displays) else {
                return nil
            }

            let appInfo = CaptureTarget.ApplicationInfo(
                bundleIdentifier: app.bundleIdentifier,
                processID: app.processID,
                applicationName: app.applicationName
            )

            return CaptureTarget(
                windowID: window.windowID,
                displayID: display.displayID,
                windowTitle: window.title ?? "",
                application: appInfo
            )
        }

        return targets.sorted {
            if $0.application.applicationName == $1.application.applicationName {
                return $0.windowTitle < $1.windowTitle
            }
            return $0.application.applicationName < $1.application.applicationName
        }
    }

    public func startCapture(target: CaptureTarget) async throws {
        if stream != nil {
            await stopCapture()
        }

        let content = try await loadShareableContent(onScreenWindowsOnly: false)

        guard let selectedWindow = content.windows.first(where: { $0.windowID == target.windowID }) else {
            throw ScreenCaptureServiceError.targetWindowNotFound(target.windowID)
        }

        guard let owningApplication = selectedWindow.owningApplication else {
            throw ScreenCaptureServiceError.targetWithoutOwningApplication(target.windowID)
        }

        guard owningApplication.processID == target.application.processID else {
            throw ScreenCaptureServiceError.targetApplicationNotFound(target.application.processID)
        }

        let targetDisplay = content.displays.first(where: { $0.displayID == target.displayID })
            ?? resolveDisplay(for: selectedWindow.frame, displays: content.displays)
            ?? content.displays.first
        guard let targetDisplay else {
            throw ScreenCaptureServiceError.displayNotFound(target.displayID)
        }

        // Meet/Chrome の無音事象を避けるため、音声は display ベースにフォールバックして取得する。
        let filter = SCContentFilter(display: targetDisplay, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = targetDisplay.width
        configuration.height = targetDisplay.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.showsCursor = false
        // 内蔵ブラウザ（同一プロセス）を確実に収録するため常に false にする
        configuration.excludesCurrentProcessAudio = false

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream

        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)

        try await stream.startCapture()
    }

    public func stopCapture() async {
        guard let stream else {
            return
        }
        do {
            try await stream.stopCapture()
        } catch {
            print("[ScreenCaptureService] stopCapture error: \(error.localizedDescription)")
        }
        self.stream = nil
    }

    private func loadShareableContent(onScreenWindowsOnly: Bool) async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: onScreenWindowsOnly)
    }

    private func resolveDisplay(for windowFrame: CGRect, displays: [SCDisplay]) -> SCDisplay? {
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        if let display = displays.first(where: { $0.frame.contains(center) }) {
            return display
        }

        let intersecting = displays
            .map { display -> (SCDisplay, CGFloat) in
                (display, display.frame.intersection(windowFrame).area)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .first

        return intersecting?.0
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else {
            return 0
        }
        return width * height
    }
}

extension ScreenCaptureService: SCStreamOutput {
    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard CMSampleBufferIsValid(sampleBuffer) else {
            return
        }

        switch type {
        case .screen:
            onVideoSampleBuffer?(sampleBuffer)
        case .audio:
            onAudioSampleBuffer?(sampleBuffer)
        @unknown default:
            break
        }
    }
}

extension ScreenCaptureService: SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenCaptureService] stream stopped: \(error.localizedDescription)")
    }
}
