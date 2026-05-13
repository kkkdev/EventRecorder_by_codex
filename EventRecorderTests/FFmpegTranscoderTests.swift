import Foundation
import XCTest
@testable import EventRecorderCore

final class FFmpegTranscoderTests: XCTestCase {
    func testTranscodeToMp3FailsWhenInputFileMissing() {
        let transcoder = FFmpegTranscoder(executableCandidates: ["/nonexistent/ffmpeg"])
        let input = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).caf")
        let output = URL(fileURLWithPath: "/tmp/output-\(UUID().uuidString).mp3")

        XCTAssertThrowsError(
            try transcoder.transcodeToMp3(inputURL: input, outputURL: output, bitrateKbps: 128)
        ) { error in
            guard case .inputFileMissing(let path) = error as? FFmpegTranscodeError else {
                XCTFail("unexpected error: \(error)")
                return
            }
            XCTAssertEqual(path, input.path)
        }
    }
}
