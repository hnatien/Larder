import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns downloaded image bytes into a small JPEG to keep on the device.
nonisolated enum PhotoDownsampler {
    /// The longest side of a stored photo, in pixels: sharp on a full-width banner, small on disk.
    static let maximumPixelSize = 1200
    static let jpegQuality = 0.8

    /// A JPEG of `data` no larger than `maximumPixelSize` on its longest side, upright, with no metadata carried over;
    /// `nil` when `data` is not an image ImageIO can read.
    static func jpeg(from data: Data, maximumPixelSize: Int = maximumPixelSize) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
