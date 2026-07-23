import CoreVideo
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
private enum CaptureFinalizationVerifier {
    static func main() throws {
        try verifyCompletionPlans()
        try verifyFinalizationGate()
        try verifyErrorPriorityAndSanitization()
        try verifyDiagnosticsAccumulator()
        try verifyLegacyManifestCompatibility()
        try verifyNoAudioManifestOutput()
        try verifySerialQueueDrain()
        try verifyVideoSampleBufferPolicy()

        print("capture finalization verification passed")
    }

    private static func verifyCompletionPlans() throws {
        let noAudioPlan = CaptureCompletionResolver.makeFinalizationPlan(
            captureDiagnostics: CaptureDiagnostics(audioSampleBufferCount: 0),
            audioDiagnostics: makeAudioDiagnostics(sampleCount: 0, nonSilentSampleCount: 0),
            audioFileName: "recording.mp3"
        )
        try expect(noAudioPlan.completionStatus == .completedWithoutAudio, "no-audio status")
        try expect(!noAudioPlan.shouldTranscodeAudio, "no-audio transcode must be disabled")
        try expect(noAudioPlan.audioFileName == nil, "no-audio MP3 name must be nil")

        let silentPlan = CaptureCompletionResolver.makeFinalizationPlan(
            captureDiagnostics: CaptureDiagnostics(
                audioSampleBufferCount: 1,
                audioWriteSuccessCount: 1
            ),
            audioDiagnostics: makeAudioDiagnostics(sampleCount: 100, nonSilentSampleCount: 0),
            audioFileName: "recording.mp3"
        )
        try expect(silentPlan.completionStatus == .completedWithWarnings, "silent status")
        try expect(silentPlan.shouldTranscodeAudio, "silent sample must be transcoded")

        let completedPlan = CaptureCompletionResolver.makeFinalizationPlan(
            captureDiagnostics: CaptureDiagnostics(
                audioSampleBufferCount: 1,
                audioWriteSuccessCount: 1
            ),
            audioDiagnostics: makeAudioDiagnostics(sampleCount: 100, nonSilentSampleCount: 10),
            audioFileName: "recording.mp3"
        )
        try expect(completedPlan.completionStatus == .completed, "completed status")
        try expect(completedPlan.shouldTranscodeAudio, "audible sample must be transcoded")
    }

    private static func verifyFinalizationGate() throws {
        var gate = CaptureFinalizationGate()
        var streamStopCount = 0
        var audioTranscodeCount = 0
        var manifestWriteCount = 0

        for _ in 0..<2 {
            guard gate.begin() else {
                continue
            }
            streamStopCount += 1
            audioTranscodeCount += 1
            manifestWriteCount += 1
        }

        try expect(streamStopCount == 1, "stream stop must run once")
        try expect(audioTranscodeCount == 1, "audio transcode must run once")
        try expect(manifestWriteCount == 1, "manifest write must run once")
    }

    private static func verifyErrorPriorityAndSanitization() throws {
        let audioError = NSError(domain: "AudioWriteErrorDomain", code: 10)
        let streamError = NSError(domain: "StreamErrorDomain", code: 20)
        let preferred = CaptureFinalizationFailureResolver.preferredError(
            audioWriteError: audioError,
            streamStopError: streamError
        ) as NSError?

        try expect(preferred?.domain == "AudioWriteErrorDomain", "audio error must take priority")
        try expect(preferred?.code == 10, "audio error code must be preserved")

        let privateDescription = "private https://example.com /Users/example/output"
        let unsafeError = NSError(
            domain: "invalid /Users/example",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: privateDescription]
        )
        let record = CaptureErrorRecord(error: unsafeError)
        let encoded = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)

        try expect(record.domain == "UnknownErrorDomain", "unsafe error domain must be sanitized")
        try expect(!encoded.contains(privateDescription), "localized description must not be persisted")
        try expect(!encoded.contains("/Users/example"), "absolute path must not be persisted")
    }

    private static func verifyDiagnosticsAccumulator() throws {
        var accumulator = CaptureDiagnosticsAccumulator()
        accumulator.recordVideoSampleBuffer()
        accumulator.recordAudioSampleBuffer(presentationTimeSeconds: 12.5)
        accumulator.recordAudioWriteSuccess()
        accumulator.recordAudioSampleBuffer(presentationTimeSeconds: 14.0)
        accumulator.recordAudioWriteFailure(
            NSError(domain: "AVFoundationErrorDomain", code: -1)
        )

        let diagnostics = accumulator.makeDiagnostics()
        try expect(diagnostics.videoSampleBufferCount == 1, "video callback count")
        try expect(diagnostics.audioSampleBufferCount == 2, "audio callback count")
        try expect(diagnostics.audioWriteSuccessCount == 1, "audio write success count")
        try expect(diagnostics.audioWriteFailureCount == 1, "audio write failure count")
        try expect(diagnostics.firstAudioSamplePTSSeconds == 12.5, "first audio PTS")
        try expect(diagnostics.lastAudioSamplePTSSeconds == 14.0, "last audio PTS")
    }

    private static func verifyLegacyManifestCompatibility() throws {
        let legacy = LegacyCaptureManifest(
            sessionID: "legacy",
            captureTarget: makeTarget(),
            intervalSeconds: 1,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 110),
            audioFileName: "recording.mp3",
            audioDiagnostics: nil,
            imageDirectoryName: "images",
            frames: []
        )
        let data = try makeEncoder().encode(legacy)
        let decoded = try makeDecoder().decode(CaptureManifest.self, from: data)

        try expect(decoded.audioFileName == "recording.mp3", "legacy audio file name")
        try expect(decoded.completionStatus == nil, "legacy completion status must be optional")
        try expect(decoded.captureDiagnostics == nil, "legacy diagnostics must be optional")
    }

    private static func verifyNoAudioManifestOutput() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("event-recorder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let manifest = CaptureManifest(
            sessionID: "no-audio",
            captureTarget: makeTarget(),
            intervalSeconds: 1,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 110),
            audioFileName: nil,
            audioDiagnostics: makeAudioDiagnostics(sampleCount: 0, nonSilentSampleCount: 0),
            imageDirectoryName: "images",
            frames: [],
            completionStatus: .completedWithoutAudio,
            captureDiagnostics: CaptureDiagnostics(videoSampleBufferCount: 10)
        )

        let manifestURL = try manifest.write(to: directory)
        let decoded = try makeDecoder().decode(
            CaptureManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let mp3URL = directory.appendingPathComponent("recording.mp3")

        try expect(decoded.completionStatus == .completedWithoutAudio, "no-audio manifest status")
        try expect(decoded.audioFileName == nil, "no-audio manifest MP3 name")
        try expect(!FileManager.default.fileExists(atPath: mp3URL.path), "no-audio MP3 must not exist")
    }

    private static func verifySerialQueueDrain() throws {
        final class Counter {
            var value = 0
        }

        let counter = Counter()
        let queue = DispatchQueue(label: "event-recorder.verification.sample")
        queue.async {
            counter.value += 1
        }
        queue.sync {}

        try expect(counter.value == 1, "serial queue drain must include queued sample")
    }

    private static func verifyVideoSampleBufferPolicy() throws {
        try expect(
            !VideoSampleBufferPolicy.shouldRetain(imageBuffer: nil),
            "screen sample without image buffer must be rejected"
        )

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            2,
            2,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        try expect(status == kCVReturnSuccess, "verification pixel buffer creation")
        try expect(
            VideoSampleBufferPolicy.shouldRetain(imageBuffer: pixelBuffer),
            "screen sample with image buffer must be retained"
        )
    }

    private static func makeAudioDiagnostics(
        sampleCount: UInt64,
        nonSilentSampleCount: UInt64
    ) -> AudioDiagnostics {
        AudioDiagnostics(
            sampleCount: sampleCount,
            nonSilentSampleCount: nonSilentSampleCount,
            silenceThreshold: 1.0e-5,
            peakAmplitude: nonSilentSampleCount == 0 ? 0 : 0.5,
            rmsAmplitude: nonSilentSampleCount == 0 ? 0 : 0.25,
            peakLevelDBFS: nonSilentSampleCount == 0 ? -160 : -6,
            rmsLevelDBFS: nonSilentSampleCount == 0 ? -160 : -12
        )
    }

    private static func makeTarget() -> CaptureTarget {
        CaptureTarget(
            windowID: 1,
            displayID: 1,
            windowTitle: "",
            application: .init(
                bundleIdentifier: "com.example.fixture",
                processID: 1,
                applicationName: "Fixture"
            )
        )
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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

private struct LegacyCaptureManifest: Codable {
    let sessionID: String
    let captureTarget: CaptureTarget
    let intervalSeconds: Double
    let startedAt: Date
    let endedAt: Date
    let audioFileName: String
    let audioDiagnostics: AudioDiagnostics?
    let imageDirectoryName: String
    let frames: [CaptureManifest.FrameRecord]
}
