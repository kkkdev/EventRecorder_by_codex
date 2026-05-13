import Foundation

public struct CaptureSettings: Codable, Equatable {
    public static let intervalRange: ClosedRange<Double> = 0.5...120.0
    public static let jpegQualityRange: ClosedRange<Double> = 0.1...1.0
    public static let bitrateRange: ClosedRange<Int> = 64...320

    public var target: CaptureTarget
    public var intervalSeconds: Double
    public var jpegQuality: Double
    public var outputDirectory: URL
    public var audioBitrateKbps: Int

    public init(
        target: CaptureTarget,
        intervalSeconds: Double = 1.0,
        jpegQuality: Double = 0.9,
        outputDirectory: URL = CaptureSettings.defaultOutputDirectory(),
        audioBitrateKbps: Int = 128
    ) {
        self.target = target
        self.intervalSeconds = intervalSeconds
        self.jpegQuality = jpegQuality
        self.outputDirectory = outputDirectory
        self.audioBitrateKbps = audioBitrateKbps
    }

    public func validated() throws -> CaptureSettings {
        guard target.windowID != 0, target.displayID != 0 else {
            throw CaptureSettingsValidationError.invalidTarget
        }
        guard Self.intervalRange.contains(intervalSeconds) else {
            throw CaptureSettingsValidationError.invalidInterval(intervalSeconds)
        }
        guard Self.jpegQualityRange.contains(jpegQuality) else {
            throw CaptureSettingsValidationError.invalidJpegQuality(jpegQuality)
        }
        guard Self.bitrateRange.contains(audioBitrateKbps) else {
            throw CaptureSettingsValidationError.invalidAudioBitrate(audioBitrateKbps)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: outputDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CaptureSettingsValidationError.invalidOutputDirectory(outputDirectory.path)
        }
        return self
    }

    public static func defaultOutputDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("EventRecorder", isDirectory: true)
    }
}

public enum CaptureSettingsValidationError: LocalizedError, Equatable {
    case invalidTarget
    case invalidInterval(Double)
    case invalidJpegQuality(Double)
    case invalidAudioBitrate(Int)
    case invalidOutputDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTarget:
            return "キャプチャ対象ウィンドウを選択してください。"
        case .invalidInterval(let value):
            return "スクショ間隔が不正です: \(value)秒（0.5〜120秒）。"
        case .invalidJpegQuality(let value):
            return "JPEG品質が不正です: \(value)（0.1〜1.0）。"
        case .invalidAudioBitrate(let value):
            return "音声ビットレートが不正です: \(value)kbps（64〜320）。"
        case .invalidOutputDirectory(let path):
            return "保存先ディレクトリが見つかりません: \(path)"
        }
    }
}
