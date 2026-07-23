import Foundation

struct CaptureFinalizationPlan: Equatable {
    let completionStatus: CaptureCompletionStatus
    let shouldTranscodeAudio: Bool
    let audioFileName: String?

    init(
        completionStatus: CaptureCompletionStatus,
        shouldTranscodeAudio: Bool,
        audioFileName: String?
    ) {
        self.completionStatus = completionStatus
        self.shouldTranscodeAudio = shouldTranscodeAudio
        self.audioFileName = audioFileName
    }
}

enum CaptureCompletionResolver {
    static func resolve(
        captureDiagnostics: CaptureDiagnostics,
        audioDiagnostics: AudioDiagnostics
    ) -> CaptureCompletionStatus {
        if captureDiagnostics.audioSampleBufferCount == 0 {
            return .completedWithoutAudio
        }
        if audioDiagnostics.isSilent {
            return .completedWithWarnings
        }
        return .completed
    }

    static func makeFinalizationPlan(
        captureDiagnostics: CaptureDiagnostics,
        audioDiagnostics: AudioDiagnostics,
        audioFileName: String
    ) -> CaptureFinalizationPlan {
        let status = resolve(
            captureDiagnostics: captureDiagnostics,
            audioDiagnostics: audioDiagnostics
        )
        if status == .completedWithoutAudio {
            return CaptureFinalizationPlan(
                completionStatus: status,
                shouldTranscodeAudio: false,
                audioFileName: nil
            )
        }
        return CaptureFinalizationPlan(
            completionStatus: status,
            shouldTranscodeAudio: true,
            audioFileName: audioFileName
        )
    }
}

enum CaptureFinalizationFailureResolver {
    static func preferredError(
        audioWriteError: Error?,
        streamStopError: Error?
    ) -> Error? {
        audioWriteError ?? streamStopError
    }
}

struct CaptureFinalizationGate {
    private(set) var isFinalizing = false

    init() {}

    mutating func begin() -> Bool {
        guard !isFinalizing else {
            return false
        }
        isFinalizing = true
        return true
    }

    mutating func reset() {
        isFinalizing = false
    }
}
