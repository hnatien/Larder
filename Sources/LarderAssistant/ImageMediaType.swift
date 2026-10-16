import Foundation

/// An image format the proxy accepts, identified from the file's leading bytes.
enum ImageMediaType: String, Sendable {
    case jpeg = "image/jpeg"
    case png = "image/png"
    case webp = "image/webp"

    init?(sniffing data: Data) {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            self = .jpeg
        } else if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            self = .png
        } else if data.starts(with: Array("RIFF".utf8)), data.dropFirst(8).starts(with: Array("WEBP".utf8)) {
            self = .webp
        } else {
            return nil
        }
    }
}
