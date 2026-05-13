import Foundation

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
    public let audioFileName: String
    public let audioDiagnostics: AudioDiagnostics?
    public let imageDirectoryName: String
    public let frames: [FrameRecord]

    public init(
        sessionID: String,
        captureTarget: CaptureTarget,
        intervalSeconds: Double,
        startedAt: Date,
        endedAt: Date,
        audioFileName: String,
        audioDiagnostics: AudioDiagnostics? = nil,
        imageDirectoryName: String,
        frames: [FrameRecord]
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
