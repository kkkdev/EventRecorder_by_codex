import CoreVideo

enum VideoSampleBufferPolicy {
    static func shouldRetain(imageBuffer: CVImageBuffer?) -> Bool {
        imageBuffer != nil
    }
}
