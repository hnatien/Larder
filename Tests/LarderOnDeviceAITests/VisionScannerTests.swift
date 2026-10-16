import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
@testable import LarderOnDeviceAI

/// Draws test images in memory.
enum TestImages {
    static func png(width: Int, height: Int, draw: (CGContext) -> Void) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        draw(context)
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// Black text lines, top to bottom, at a large size.
    static func text(_ lines: [String]) throws -> Data {
        let lineHeight = 90
        return try png(width: 1400, height: lineHeight * (lines.count + 1)) { context in
            let font = CTFontCreateWithName("Helvetica" as CFString, 60, nil)
            for (index, line) in lines.enumerated() {
                let attributed = NSAttributedString(string: line, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
                ])
                context.textPosition = CGPoint(x: 60, y: lineHeight * (lines.count - index))
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            }
        }
    }

    /// An EAN-13 barcode for `digits` (13 digits including the check digit).
    static func ean13(_ digits: String) throws -> Data {
        let left = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"]
        let even = ["0100111", "0110011", "0011011", "0100001", "0011101", "0111001", "0000101", "0010001", "0001001", "0010111"]
        let right = ["1110010", "1100110", "1101100", "1000010", "1011100", "1001110", "1010000", "1000100", "1001000", "1110100"]
        let parity = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]
        let values = digits.compactMap(\.wholeNumberValue)
        try #require(values.count == 13)
        var modules = "101"
        for (index, value) in values[1...6].enumerated() {
            modules += Array(parity[values[0]])[index] == "L" ? left[value] : even[value]
        }
        modules += "01010"
        for value in values[7...12] {
            modules += right[value]
        }
        modules += "101"
        let moduleWidth = 6
        let quiet = 12 * moduleWidth
        return try png(width: modules.count * moduleWidth + 2 * quiet, height: 300) { context in
            for (index, module) in modules.enumerated() where module == "1" {
                context.fill(CGRect(x: quiet + index * moduleWidth, y: 30, width: moduleWidth, height: 240))
            }
        }
    }
}

struct VisionScannerTests {
    @Test(arguments: [Data(), Data("plain text".utf8), Data([0xFF, 0xD8, 0xFF])])
    func unreadableDataIsRejectedBeforeVision(data: Data) async {
        await #expect(throws: ImageScanError.unreadableImage) { try await DocumentTextExtractor().lines(in: data) }
        await #expect(throws: ImageScanError.unreadableImage) { try await BarcodeReader().barcodes(in: data) }
    }

    @Test func printedLinesAreReadInOrder() async throws {
        let image = try TestImages.text(["Oat Milk 1.80", "Sourdough Loaf 2.50", "TOTAL 4.30"])
        let lines = try await DocumentTextExtractor().lines(in: image)
        let lowered = lines.map { $0.lowercased() }
        let milk = try #require(lowered.firstIndex { $0.contains("oat milk") })
        let loaf = try #require(lowered.firstIndex { $0.contains("sourdough") })
        #expect(milk < loaf)
        #expect(ReceiptLineFilter.pantryCandidates(from: lines).map { $0.lowercased() } == ["oat milk", "sourdough loaf"])
    }

    @Test func ean13BarcodeIsRead() async throws {
        let codes = try await BarcodeReader().barcodes(in: TestImages.ean13("4006381333931"))
        #expect(codes == ["4006381333931"])
    }

    @Test func imagesWithoutBarcodesGiveNone() async throws {
        let codes = try await BarcodeReader().barcodes(in: TestImages.text(["Leeks"]))
        #expect(codes.isEmpty)
    }
}
