import Foundation
import ImageIO

/// Why a photo could not be scanned.
public enum ImageScanError: Error, Hashable, Sendable {
    /// The data is not a decodable image.
    case unreadableImage
    /// Vision could not analyse the image.
    case recognitionFailed
}

/// Checks photo data before it reaches Vision.
nonisolated enum ImageDataValidator {
    /// Throws `ImageScanError.unreadableImage` unless `data` holds at least one decodable image.
    static func validate(_ data: Data) throws {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) != nil,
              CGImageSourceGetCount(source) > 0
        else { throw ImageScanError.unreadableImage }
    }
}
