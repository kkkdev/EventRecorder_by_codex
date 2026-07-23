import Foundation
import XCTest
@testable import EventRecorderCore

final class CaptureFinalizationTests: XCTestCase {
    func testCompletionResolverReturnsCompletedWithoutAudioForZeroCallbacks() {
        let plan = CaptureCompletionResolver.makeFinalizationPlan(
            captureDiagnostics: CaptureDiagnostics(audioSampleBufferCount: 0),
            audioDiagnostics: makeAudioDiagnostics(sampleCount: 0, nonSilentSampleCount: 0),
            audioFileName: "recording.mp3"
        )

        XCTAssertEqual(plan.completionStatus, .completedWithoutAudio)
        XCTAssertFalse(plan.shouldTranscodeAudio)
        XCTAssertNil(plan.audioFileName)
    }

    func testCompletionResolverReturnsWarningForSilentSamples() {
        let plan = CaptureCompletionResolver.makeFinalizationPlan(
            captureDiagnostics: CaptureDiagnostics(
                audioSampleBufferCount: 1,
                audioWriteSuccessCount: 1
            ),
            audioDiagnostics: makeAudioDiagnostics(sampleCount: 100, nonSilentSampleCount: 0),
            audioFileName: "recording.mp3"
        )

        XCTAssertEqual(plan.completionStatus, .completedWithWarnings)
        XCTAssertTrue(plan.shouldTranscodeAudio)
        XCTAssertEqual(plan.audioFileName, "recording.mp3")
    }

    func testCompletionResolverReturnsCompletedForAudibleSamples() {
        let plan = CaptureCompletionResolver.makeFinalizationPlan(
            captureDiagnostics: CaptureDiagnostics(
                audioSampleBufferCount: 1,
                audioWriteSuccessCount: 1
            ),
            audioDiagnostics: makeAudioDiagnostics(sampleCount: 100, nonSilentSampleCount: 10),
            audioFileName: "recording.mp3"
        )

        XCTAssertEqual(plan.completionStatus, .completed)
        XCTAssertTrue(plan.shouldTranscodeAudio)
        XCTAssertEqual(plan.audioFileName, "recording.mp3")
    }

    func testFinalizationGateAllowsOneBeginUntilReset() {
        var gate = CaptureFinalizationGate()

        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.begin())
        XCTAssertTrue(gate.isFinalizing)

        gate.reset()

        XCTAssertTrue(gate.begin())
    }

    func testRepeatedStopRequestsRunEachFinalizationSideEffectOnce() {
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

        XCTAssertEqual(streamStopCount, 1)
        XCTAssertEqual(audioTranscodeCount, 1)
        XCTAssertEqual(manifestWriteCount, 1)
    }

    func testAudioWriteErrorTakesPriorityOverStreamAndNoAudioFallback() {
        let audioError = NSError(domain: "AudioWriteErrorDomain", code: 10)
        let streamError = NSError(domain: "StreamErrorDomain", code: 20)

        let preferred = CaptureFinalizationFailureResolver.preferredError(
            audioWriteError: audioError,
            streamStopError: streamError
        ) as NSError?

        XCTAssertEqual(preferred?.domain, "AudioWriteErrorDomain")
        XCTAssertEqual(preferred?.code, 10)
    }

    func testCaptureStateCanStopOnlyWhileCapturing() {
        XCTAssertFalse(CaptureState.idle.canStop)
        XCTAssertFalse(CaptureState.preparing.canStop)
        XCTAssertTrue(CaptureState.capturing.canStop)
        XCTAssertFalse(CaptureState.stopping.canStop)
    }

    private func makeAudioDiagnostics(
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
}
