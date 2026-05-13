import Foundation

public protocol FFmpegTranscoderProtocol {
    func locateFFmpeg() -> URL?
    func transcodeToMp3(inputURL: URL, outputURL: URL, bitrateKbps: Int) throws
}

public enum FFmpegTranscodeError: LocalizedError {
    case ffmpegNotFound
    case inputFileMissing(String)
    case processFailed(code: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "ffmpegが見つかりません。`brew install ffmpeg` を実行してください。"
        case .inputFileMissing(let path):
            return "音声入力ファイルが見つかりません: \(path)"
        case .processFailed(let code, let message):
            let shortReason = message
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "unknown error"
            return "ffmpeg変換に失敗しました (code=\(code)): \(shortReason)"
        }
    }
}

public final class FFmpegTranscoder: FFmpegTranscoderProtocol {
    private let executableCandidates: [String]

    public init(executableCandidates: [String] = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "ffmpeg"
    ]) {
        self.executableCandidates = executableCandidates
    }

    public func locateFFmpeg() -> URL? {
        for candidate in executableCandidates {
            if candidate.hasPrefix("/") {
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return URL(fileURLWithPath: candidate)
                }
                continue
            }

            if let fromPath = locateFromPATH(executableName: candidate) {
                return fromPath
            }
        }
        return nil
    }

    public func transcodeToMp3(inputURL: URL, outputURL: URL, bitrateKbps: Int) throws {
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw FFmpegTranscodeError.inputFileMissing(inputURL.path)
        }

        guard let executableURL = locateFFmpeg() else {
            throw FFmpegTranscodeError.ffmpegNotFound
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = FFmpegCommandBuilder.buildArguments(
            inputURL: inputURL,
            outputURL: outputURL,
            bitrateKbps: bitrateKbps
        )

        let stdErr = Pipe()
        process.standardError = stdErr
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        let errorData = stdErr.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: errorData, encoding: .utf8) ?? "unknown error"
        guard process.terminationStatus == 0 else {
            throw FFmpegTranscodeError.processFailed(code: process.terminationStatus, message: message)
        }
    }

    private func locateFromPATH(executableName: String) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [executableName]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !result.isEmpty
        else {
            return nil
        }
        return URL(fileURLWithPath: result)
    }
}
