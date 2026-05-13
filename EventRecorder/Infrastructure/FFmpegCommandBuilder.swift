import Foundation

public enum FFmpegCommandBuilder {
    public static func normalizedBitrateKbps(_ bitrateKbps: Int) -> Int {
        min(max(bitrateKbps, 64), 320)
    }

    public static func buildArguments(
        inputURL: URL,
        outputURL: URL,
        bitrateKbps: Int
    ) -> [String] {
        let normalized = normalizedBitrateKbps(bitrateKbps)
        return [
            "-y",
            "-hide_banner",
            "-loglevel", "error",
            "-i", inputURL.path,
            "-vn",
            "-acodec", "libmp3lame",
            "-b:a", "\(normalized)k",
            outputURL.path
        ]
    }
}
