import Foundation

public enum AudioInputPreflightError: LocalizedError, Equatable {
    case fileMissing(String)
    case fileEmpty(String)

    public var errorDescription: String? {
        switch self {
        case .fileMissing(let path):
            return "音声一時ファイルが見つかりません: \(path)"
        case .fileEmpty(let path):
            return "音声一時ファイルが空です: \(path)"
        }
    }
}

public enum AudioInputPreflight {
    public static func validate(tempAudioURL: URL, fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: tempAudioURL.path) else {
            throw AudioInputPreflightError.fileMissing(tempAudioURL.path)
        }

        let attributes = try fileManager.attributesOfItem(atPath: tempAudioURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard fileSize > 0 else {
            throw AudioInputPreflightError.fileEmpty(tempAudioURL.path)
        }
    }
}
