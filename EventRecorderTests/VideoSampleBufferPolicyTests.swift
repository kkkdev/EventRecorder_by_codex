import CoreVideo
import XCTest
@testable import EventRecorderCore

final class VideoSampleBufferPolicyTests: XCTestCase {
    func testRejectsSampleWithoutImageBuffer() {
        XCTAssertFalse(VideoSampleBufferPolicy.shouldRetain(imageBuffer: nil))
    }

    func testRetainsSampleWithImageBuffer() throws {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            2,
            2,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )

        XCTAssertEqual(status, kCVReturnSuccess)
        XCTAssertTrue(VideoSampleBufferPolicy.shouldRetain(imageBuffer: pixelBuffer))
    }
}
