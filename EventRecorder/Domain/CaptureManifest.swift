import Foundation

public enum CaptureCompletionStatus: String, Codable, Equatable {
    case completed
    case completedWithWarnings
    case completedWithoutAudio
}

public struct CaptureErrorRecord: Codable, Equatable {
    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) {
        self.domain = Self.sanitize(domain: domain)
        self.code = code
    }

    public init(error: Error) {
        let nsError = error as NSError
        self.init(domain: nsError.domain, code: nsError.code)
    }

    private static func sanitize(domain: String) -> String {
        guard !domain.isEmpty, domain.utf8.count <= 128 else {
            return "UnknownErrorDomain"
        }

        let isAllowedASCII = domain.utf8.allSatisfy { byte in
            switch byte {
            case 45, 46, 48...57, 65...90, 95, 97...122:
                return true
            default:
                return false
            }
        }
        guard isAllowedASCII else {
            return "UnknownErrorDomain"
        }
        return domain
    }
}

public struct CaptureDiagnostics: Codable, Equatable {
    public let videoSampleBufferCount: UInt64
    public let audioSampleBufferCount: UInt64
    public let audioWriteSuccessCount: UInt64
    public let audioWriteFailureCount: UInt64
    public let firstAudioSamplePTSSeconds: Double?
    public let lastAudioSamplePTSSeconds: Double?
    public let audioWriteError: CaptureErrorRecord?
    public let streamStopError: CaptureErrorRecord?

    public init(
        videoSampleBufferCount: UInt64 = 0,
        audioSampleBufferCount: UInt64 = 0,
        audioWriteSuccessCount: UInt64 = 0,
        audioWriteFailureCount: UInt64 = 0,
        firstAudioSamplePTSSeconds: Double? = nil,
        lastAudioSamplePTSSeconds: Double? = nil,
        audioWriteError: CaptureErrorRecord? = nil,
        streamStopError: CaptureErrorRecord? = nil
    ) {
        self.videoSampleBufferCount = videoSampleBufferCount
        self.audioSampleBufferCount = audioSampleBufferCount
        self.audioWriteSuccessCount = audioWriteSuccessCount
        self.audioWriteFailureCount = audioWriteFailureCount
        self.firstAudioSamplePTSSeconds = firstAudioSamplePTSSeconds
        self.lastAudioSamplePTSSeconds = lastAudioSamplePTSSeconds
        self.audioWriteError = audioWriteError
        self.streamStopError = streamStopError
    }
}

public struct CaptureDiagnosticsAccumulator: Equatable {
    private var videoSampleBufferCount: UInt64 = 0
    private var audioSampleBufferCount: UInt64 = 0
    private var audioWriteSuccessCount: UInt64 = 0
    private var audioWriteFailureCount: UInt64 = 0
    private var firstAudioSamplePTSSeconds: Double?
    private var lastAudioSamplePTSSeconds: Double?
    private var audioWriteError: CaptureErrorRecord?
    private var streamStopError: CaptureErrorRecord?

    public init() {}

    public mutating func recordVideoSampleBuffer() {
        videoSampleBufferCount += 1
    }

    public mutating func recordAudioSampleBuffer(presentationTimeSeconds: Double) {
        audioSampleBufferCount += 1
        guard presentationTimeSeconds.isFinite else {
            return
        }
        if firstAudioSamplePTSSeconds == nil {
            firstAudioSamplePTSSeconds = presentationTimeSeconds
        }
        lastAudioSamplePTSSeconds = presentationTimeSeconds
    }

    public mutating func recordAudioWriteSuccess() {
        audioWriteSuccessCount += 1
    }

    public mutating func recordAudioWriteFailure(_ error: Error) {
        audioWriteFailureCount += 1
        if audioWriteError == nil {
            audioWriteError = CaptureErrorRecord(error: error)
        }
    }

    public mutating func recordStreamStopFailure(_ error: Error) {
        if streamStopError == nil {
            streamStopError = CaptureErrorRecord(error: error)
        }
    }

    public func makeDiagnostics() -> CaptureDiagnostics {
        CaptureDiagnostics(
            videoSampleBufferCount: videoSampleBufferCount,
            audioSampleBufferCount: audioSampleBufferCount,
            audioWriteSuccessCount: audioWriteSuccessCount,
            audioWriteFailureCount: audioWriteFailureCount,
            firstAudioSamplePTSSeconds: firstAudioSamplePTSSeconds,
            lastAudioSamplePTSSeconds: lastAudioSamplePTSSeconds,
            audioWriteError: audioWriteError,
            streamStopError: streamStopError
        )
    }
}

public struct CaptureManifest: Codable, Equatable {
    public struct FrameRecord: Codable, Equatable, Identifiable {
        public let id: String
        public let fileName: String
        public let capturePTSSeconds: Double
        public let savedAt: Date

        public init(fileName: String, capturePTSSeconds: Double, savedAt: Date) {
            self.id = fileName
            self.fileName = fileName
            self.capturePTSSeconds = capturePTSSeconds
            self.savedAt = savedAt
        }
    }

    public let sessionID: String
    public let captureTarget: CaptureTarget
    public let intervalSeconds: Double
    public let startedAt: Date
    public let endedAt: Date
    public let audioFileName: String?
    public let audioDiagnostics: AudioDiagnostics?
    public let imageDirectoryName: String
    public let frames: [FrameRecord]
    public let completionStatus: CaptureCompletionStatus?
    public let captureDiagnostics: CaptureDiagnostics?

    public init(
        sessionID: String,
        captureTarget: CaptureTarget,
        intervalSeconds: Double,
        startedAt: Date,
        endedAt: Date,
        audioFileName: String?,
        audioDiagnostics: AudioDiagnostics? = nil,
        imageDirectoryName: String,
        frames: [FrameRecord],
        completionStatus: CaptureCompletionStatus? = nil,
        captureDiagnostics: CaptureDiagnostics? = nil
    ) {
        self.sessionID = sessionID
        self.captureTarget = captureTarget
        self.intervalSeconds = intervalSeconds
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.audioFileName = audioFileName
        self.audioDiagnostics = audioDiagnostics
        self.imageDirectoryName = imageDirectoryName
        self.frames = frames
        self.completionStatus = completionStatus
        self.captureDiagnostics = captureDiagnostics
    }

    public func write(to directory: URL, fileName: String = "manifest.json") throws -> URL {
        let manifestURL = directory.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: manifestURL, options: .atomic)
        return manifestURL
    }
}
