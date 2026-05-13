import AVFoundation
import CoreMedia
import Foundation

public protocol AudioFileWriting {
    func start(outputURL: URL) throws
    func append(sampleBuffer: CMSampleBuffer) throws
    func diagnosticsSnapshot() -> AudioDiagnostics
    func stop()
}

public enum AudioFileWriterError: LocalizedError {
    case notStarted
    case invalidFormatDescription
    case failedToBuildAudioFormat
    case failedToAllocatePCMBuffer
    case failedToCopyPCM(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .notStarted:
            return "音声書き込みが開始されていません。"
        case .invalidFormatDescription:
            return "音声フォーマット情報の取得に失敗しました。"
        case .failedToBuildAudioFormat:
            return "音声フォーマットの構築に失敗しました。"
        case .failedToAllocatePCMBuffer:
            return "PCMバッファの確保に失敗しました。"
        case .failedToCopyPCM(let status):
            return "PCMコピーに失敗しました: \(status)"
        }
    }
}

public final class AudioFileWriter: AudioFileWriting {
    private var outputURL: URL?
    private var audioFile: AVAudioFile?
    private var diagnosticsAccumulator = AudioDiagnosticsAccumulator()

    public init() {}

    public func start(outputURL: URL) throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.outputURL = outputURL
        self.audioFile = nil
        diagnosticsAccumulator = AudioDiagnosticsAccumulator()
    }

    public func append(sampleBuffer: CMSampleBuffer) throws {
        guard let outputURL else {
            throw AudioFileWriterError.notStarted
        }

        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            throw AudioFileWriterError.invalidFormatDescription
        }

        var asbd = asbdPointer.pointee
        guard let audioFormat = AVAudioFormat(streamDescription: &asbd) else {
            throw AudioFileWriterError.failedToBuildAudioFormat
        }

        let frameCount = UInt32(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            throw AudioFileWriterError.failedToAllocatePCMBuffer
        }

        pcmBuffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else {
            throw AudioFileWriterError.failedToCopyPCM(status: status)
        }

        if audioFile == nil {
            audioFile = try AVAudioFile(
                forWriting: outputURL,
                settings: audioFormat.settings,
                commonFormat: audioFormat.commonFormat,
                interleaved: audioFormat.isInterleaved
            )
        }

        try audioFile?.write(from: pcmBuffer)
        appendDiagnostics(from: pcmBuffer)
    }

    public func diagnosticsSnapshot() -> AudioDiagnostics {
        diagnosticsAccumulator.makeDiagnostics()
    }

    public func stop() {
        audioFile = nil
        outputURL = nil
    }

    private func appendDiagnostics(from pcmBuffer: AVAudioPCMBuffer) {
        let frameLength = Int(pcmBuffer.frameLength)
        guard frameLength > 0 else {
            return
        }

        let channelCount = Int(pcmBuffer.format.channelCount)
        if channelCount <= 0 {
            return
        }

        if let floatData = pcmBuffer.floatChannelData {
            if pcmBuffer.format.isInterleaved {
                let totalSamples = frameLength * channelCount
                diagnosticsAccumulator.appendFloatSamples(
                    UnsafeBufferPointer(start: floatData[0], count: totalSamples)
                )
                return
            }

            for channelIndex in 0..<channelCount {
                diagnosticsAccumulator.appendFloatSamples(
                    UnsafeBufferPointer(start: floatData[channelIndex], count: frameLength)
                )
            }
            return
        }

        if let int16Data = pcmBuffer.int16ChannelData {
            if pcmBuffer.format.isInterleaved {
                let totalSamples = frameLength * channelCount
                diagnosticsAccumulator.appendInt16Samples(
                    UnsafeBufferPointer(start: int16Data[0], count: totalSamples)
                )
                return
            }

            for channelIndex in 0..<channelCount {
                diagnosticsAccumulator.appendInt16Samples(
                    UnsafeBufferPointer(start: int16Data[channelIndex], count: frameLength)
                )
            }
            return
        }

        if let int32Data = pcmBuffer.int32ChannelData {
            if pcmBuffer.format.isInterleaved {
                let totalSamples = frameLength * channelCount
                diagnosticsAccumulator.appendInt32Samples(
                    UnsafeBufferPointer(start: int32Data[0], count: totalSamples)
                )
                return
            }

            for channelIndex in 0..<channelCount {
                diagnosticsAccumulator.appendInt32Samples(
                    UnsafeBufferPointer(start: int32Data[channelIndex], count: frameLength)
                )
            }
        }
    }
}
