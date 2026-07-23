import Foundation
import XCTest
@testable import EventRecorderCore

final class CaptureManifestTests: XCTestCase {
    func testDecodesLegacyManifestWithoutNewOptionalFields() throws {
        let legacy = LegacyCaptureManifest(
            sessionID: "20260723_145656",
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

        XCTAssertEqual(decoded.sessionID, legacy.sessionID)
        XCTAssertEqual(decoded.audioFileName, "recording.mp3")
        XCTAssertNil(decoded.completionStatus)
        XCTAssertNil(decoded.captureDiagnostics)
    }

    func testRoundTripsAllCompletionStatuses() throws {
        let statuses: [(CaptureCompletionStatus, String?)] = [
            (.completed, "recording.mp3"),
            (.completedWithWarnings, "recording.mp3"),
            (.completedWithoutAudio, nil)
        ]

        for (status, audioFileName) in statuses {
            let manifest = makeManifest(status: status, audioFileName: audioFileName)
            let decoded = try makeDecoder().decode(
                CaptureManifest.self,
                from: makeEncoder().encode(manifest)
            )

            XCTAssertEqual(decoded, manifest)
        }
    }

    func testDiagnosticsAccumulatorTracksCallbacksWritesPTSAndFirstErrors() {
        var accumulator = CaptureDiagnosticsAccumulator()
        accumulator.recordVideoSampleBuffer()
        accumulator.recordVideoSampleBuffer()
        accumulator.recordAudioSampleBuffer(presentationTimeSeconds: 12.5)
        accumulator.recordAudioWriteSuccess()
        accumulator.recordAudioSampleBuffer(presentationTimeSeconds: .infinity)
        accumulator.recordAudioWriteFailure(
            NSError(domain: "AVFoundationErrorDomain", code: -1)
        )
        accumulator.recordAudioSampleBuffer(presentationTimeSeconds: 14.0)
        accumulator.recordAudioWriteFailure(
            NSError(domain: "IgnoredSecondErrorDomain", code: -2)
        )
        accumulator.recordStreamStopFailure(
            NSError(domain: "SCStreamErrorDomain", code: -3)
        )

        let diagnostics = accumulator.makeDiagnostics()

        XCTAssertEqual(diagnostics.videoSampleBufferCount, 2)
        XCTAssertEqual(diagnostics.audioSampleBufferCount, 3)
        XCTAssertEqual(diagnostics.audioWriteSuccessCount, 1)
        XCTAssertEqual(diagnostics.audioWriteFailureCount, 2)
        XCTAssertEqual(diagnostics.firstAudioSamplePTSSeconds, 12.5)
        XCTAssertEqual(diagnostics.lastAudioSamplePTSSeconds, 14.0)
        XCTAssertEqual(
            diagnostics.audioWriteError,
            CaptureErrorRecord(domain: "AVFoundationErrorDomain", code: -1)
        )
        XCTAssertEqual(
            diagnostics.streamStopError,
            CaptureErrorRecord(domain: "SCStreamErrorDomain", code: -3)
        )
    }

    func testErrorRecordDoesNotPersistLocalizedDescriptionOrInvalidDomain() throws {
        let secretDescription = "private title https://example.com /Users/example/output"
        let error = NSError(
            domain: "invalid domain /Users/example",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: secretDescription]
        )

        let record = CaptureErrorRecord(error: error)
        let json = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)

        XCTAssertEqual(record.domain, "UnknownErrorDomain")
        XCTAssertEqual(record.code, 42)
        XCTAssertFalse(json.contains(secretDescription))
        XCTAssertFalse(json.contains("/Users/example"))
        XCTAssertEqual(
            CaptureErrorRecord(domain: "個人名ErrorDomain", code: 1).domain,
            "UnknownErrorDomain"
        )
    }

    private func makeManifest(
        status: CaptureCompletionStatus,
        audioFileName: String?
    ) -> CaptureManifest {
        CaptureManifest(
            sessionID: "20260723_145656",
            captureTarget: makeTarget(),
            intervalSeconds: 1,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 110),
            audioFileName: audioFileName,
            audioDiagnostics: nil,
            imageDirectoryName: "images",
            frames: [],
            completionStatus: status,
            captureDiagnostics: CaptureDiagnostics(
                videoSampleBufferCount: 10,
                audioSampleBufferCount: audioFileName == nil ? 0 : 10,
                audioWriteSuccessCount: audioFileName == nil ? 0 : 10
            )
        )
    }

    private func makeTarget() -> CaptureTarget {
        CaptureTarget(
            windowID: 10,
            displayID: 20,
            windowTitle: "テスト",
            application: .init(
                bundleIdentifier: "com.example.test",
                processID: 30,
                applicationName: "Test"
            )
        )
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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
