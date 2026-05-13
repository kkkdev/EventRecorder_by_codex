import Foundation
import XCTest
@testable import EventRecorderCore

final class FFmpegCommandBuilderTests: XCTestCase {
    func testBuildArgumentsUsesExpectedOrder() {
        let input = URL(fileURLWithPath: "/tmp/input.caf")
        let output = URL(fileURLWithPath: "/tmp/output.mp3")

        let args = FFmpegCommandBuilder.buildArguments(inputURL: input, outputURL: output, bitrateKbps: 128)

        XCTAssertEqual(
            args,
            [
                "-y",
                "-hide_banner",
                "-loglevel", "error",
                "-i", "/tmp/input.caf",
                "-vn",
                "-acodec", "libmp3lame",
                "-b:a", "128k",
                "/tmp/output.mp3"
            ]
        )
    }

    func testNormalizedBitrateClampsToSupportedRange() {
        XCTAssertEqual(FFmpegCommandBuilder.normalizedBitrateKbps(32), 64)
        XCTAssertEqual(FFmpegCommandBuilder.normalizedBitrateKbps(160), 160)
        XCTAssertEqual(FFmpegCommandBuilder.normalizedBitrateKbps(512), 320)
    }
}
