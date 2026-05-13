import XCTest
@testable import EventRecorderCore

final class AudioDiagnosticsTests: XCTestCase {
    func testAccumulatorMarksSilentForAllZeroFloatSamples() {
        var accumulator = AudioDiagnosticsAccumulator(silenceThreshold: 1.0e-5)
        let samples = Array(repeating: Float(0), count: 48_000)

        samples.withUnsafeBufferPointer { buffer in
            accumulator.appendFloatSamples(buffer)
        }

        let diagnostics = accumulator.makeDiagnostics()
        XCTAssertEqual(diagnostics.sampleCount, 48_000)
        XCTAssertEqual(diagnostics.nonSilentSampleCount, 0)
        XCTAssertTrue(diagnostics.isSilent)
        XCTAssertEqual(diagnostics.peakAmplitude, 0, accuracy: 1.0e-12)
        XCTAssertEqual(diagnostics.rmsAmplitude, 0, accuracy: 1.0e-12)
        XCTAssertEqual(diagnostics.peakLevelDBFS, -160.0, accuracy: 1.0e-12)
    }

    func testAccumulatorCalculatesPeakAndRMSForNonSilentSamples() {
        var accumulator = AudioDiagnosticsAccumulator(silenceThreshold: 1.0e-5)
        let samples: [Float] = [0, 0.25, -0.5, 0.5, -0.25, 0]

        samples.withUnsafeBufferPointer { buffer in
            accumulator.appendFloatSamples(buffer)
        }

        let diagnostics = accumulator.makeDiagnostics()
        XCTAssertEqual(diagnostics.sampleCount, UInt64(samples.count))
        XCTAssertEqual(diagnostics.nonSilentSampleCount, 4)
        XCTAssertFalse(diagnostics.isSilent)
        XCTAssertEqual(diagnostics.peakAmplitude, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(diagnostics.peakLevelDBFS, -6.0206, accuracy: 0.01)
        XCTAssertGreaterThan(diagnostics.rmsAmplitude, 0.30)
        XCTAssertLessThan(diagnostics.rmsAmplitude, 0.35)
    }

    func testAccumulatorNormalizesInt16AndInt32Samples() {
        var int16Accumulator = AudioDiagnosticsAccumulator(silenceThreshold: 1.0e-6)
        let int16Samples: [Int16] = [Int16.min, Int16.max, 0]
        int16Samples.withUnsafeBufferPointer { buffer in
            int16Accumulator.appendInt16Samples(buffer)
        }

        let int16Diagnostics = int16Accumulator.makeDiagnostics()
        XCTAssertEqual(int16Diagnostics.sampleCount, 3)
        XCTAssertEqual(int16Diagnostics.nonSilentSampleCount, 2)
        XCTAssertEqual(int16Diagnostics.peakAmplitude, 1.0, accuracy: 1.0e-6)

        var int32Accumulator = AudioDiagnosticsAccumulator(silenceThreshold: 1.0e-6)
        let int32Samples: [Int32] = [Int32.min, Int32.max, 0]
        int32Samples.withUnsafeBufferPointer { buffer in
            int32Accumulator.appendInt32Samples(buffer)
        }

        let int32Diagnostics = int32Accumulator.makeDiagnostics()
        XCTAssertEqual(int32Diagnostics.sampleCount, 3)
        XCTAssertEqual(int32Diagnostics.nonSilentSampleCount, 2)
        XCTAssertEqual(int32Diagnostics.peakAmplitude, 1.0, accuracy: 1.0e-6)
    }
}
