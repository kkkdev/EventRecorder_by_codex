import Foundation

public struct AudioDiagnostics: Codable, Equatable {
    public let sampleCount: UInt64
    public let nonSilentSampleCount: UInt64
    public let silenceThreshold: Double
    public let peakAmplitude: Double
    public let rmsAmplitude: Double
    public let peakLevelDBFS: Double
    public let rmsLevelDBFS: Double

    public init(
        sampleCount: UInt64,
        nonSilentSampleCount: UInt64,
        silenceThreshold: Double,
        peakAmplitude: Double,
        rmsAmplitude: Double,
        peakLevelDBFS: Double,
        rmsLevelDBFS: Double
    ) {
        self.sampleCount = sampleCount
        self.nonSilentSampleCount = nonSilentSampleCount
        self.silenceThreshold = silenceThreshold
        self.peakAmplitude = peakAmplitude
        self.rmsAmplitude = rmsAmplitude
        self.peakLevelDBFS = peakLevelDBFS
        self.rmsLevelDBFS = rmsLevelDBFS
    }

    public var isSilent: Bool {
        sampleCount == 0 || nonSilentSampleCount == 0
    }

    public static func decibels(fromLinearAmplitude amplitude: Double) -> Double {
        guard amplitude > 0 else {
            return minimumDecibelFloor
        }
        return max(minimumDecibelFloor, 20.0 * log10(amplitude))
    }

    private static let minimumDecibelFloor = -160.0
}

public struct AudioDiagnosticsAccumulator: Equatable {
    public let silenceThreshold: Double

    private var sampleCount: UInt64 = 0
    private var nonSilentSampleCount: UInt64 = 0
    private var sumOfSquares: Double = 0
    private var peakAmplitude: Double = 0

    public init(silenceThreshold: Double = 1.0e-5) {
        self.silenceThreshold = max(0, silenceThreshold)
    }

    public mutating func appendFloatSamples(_ samples: UnsafeBufferPointer<Float>) {
        for sample in samples {
            appendNormalizedSample(Double(sample))
        }
    }

    public mutating func appendInt16Samples(_ samples: UnsafeBufferPointer<Int16>) {
        let normalizer = 32768.0
        for sample in samples {
            appendNormalizedSample(Double(sample) / normalizer)
        }
    }

    public mutating func appendInt32Samples(_ samples: UnsafeBufferPointer<Int32>) {
        let normalizer = 2_147_483_648.0
        for sample in samples {
            appendNormalizedSample(Double(sample) / normalizer)
        }
    }

    public func makeDiagnostics() -> AudioDiagnostics {
        let rmsAmplitude = sampleCount == 0
            ? 0
            : sqrt(sumOfSquares / Double(sampleCount))

        return AudioDiagnostics(
            sampleCount: sampleCount,
            nonSilentSampleCount: nonSilentSampleCount,
            silenceThreshold: silenceThreshold,
            peakAmplitude: peakAmplitude,
            rmsAmplitude: rmsAmplitude,
            peakLevelDBFS: AudioDiagnostics.decibels(fromLinearAmplitude: peakAmplitude),
            rmsLevelDBFS: AudioDiagnostics.decibels(fromLinearAmplitude: rmsAmplitude)
        )
    }

    private mutating func appendNormalizedSample(_ sample: Double) {
        sampleCount += 1

        let absolute = abs(sample)
        if absolute > silenceThreshold {
            nonSilentSampleCount += 1
        }
        if absolute > peakAmplitude {
            peakAmplitude = absolute
        }

        sumOfSquares += sample * sample
    }
}
