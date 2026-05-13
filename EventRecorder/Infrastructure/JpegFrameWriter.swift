import CoreImage
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

public protocol JpegFrameWriting {
    func write(sampleBuffer: CMSampleBuffer, to outputURL: URL, quality: Double) throws
}

public enum JpegFrameWriterError: LocalizedError {
    case invalidImageBuffer
    case failedToCreateCGImage
    case failedToCreateDestination
    case failedToFinalize

    public var errorDescription: String? {
        switch self {
        case .invalidImageBuffer:
            return "映像サンプルから画像バッファを取得できません。"
        case .failedToCreateCGImage:
            return "CGImage生成に失敗しました。"
        case .failedToCreateDestination:
            return "JPEG保存先の作成に失敗しました。"
        case .failedToFinalize:
            return "JPEG保存に失敗しました。"
        }
    }
}

public final class JpegFrameWriter: JpegFrameWriting {
    private let ciContext: CIContext

    public init(ciContext: CIContext = CIContext()) {
        self.ciContext = ciContext
    }

    public func write(sampleBuffer: CMSampleBuffer, to outputURL: URL, quality: Double) throws {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw JpegFrameWriterError.invalidImageBuffer
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = ciImage.extent
        guard let cgImage = ciContext.createCGImage(ciImage, from: rect) else {
            throw JpegFrameWriterError.failedToCreateCGImage
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw JpegFrameWriterError.failedToCreateDestination
        }

        let options: CFDictionary = [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary

        CGImageDestinationAddImage(destination, cgImage, options)
        guard CGImageDestinationFinalize(destination) else {
            throw JpegFrameWriterError.failedToFinalize
        }
    }
}
