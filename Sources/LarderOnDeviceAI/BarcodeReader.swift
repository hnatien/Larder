import Foundation
import Vision

/// Reads retail product barcodes (EAN-13, EAN-8, UPC-A and UPC-E) from a still photo.
///
/// Live camera scanning is out of scope for this module; the app target wraps `DataScannerViewController` for it.
/// Vision reports UPC-A codes as EAN-13 with a leading zero.
public nonisolated struct BarcodeReader: Sendable {
    /// Creates a reader.
    public init() {}

    /// The distinct numeric payloads in `imageData`, in the order Vision reports them.
    public func barcodes(in imageData: Data) async throws -> [String] {
        try ImageDataValidator.validate(imageData)
        var request = DetectBarcodesRequest()
        request.symbologies = [.ean13, .ean8, .upce]
        let observations: [BarcodeObservation]
        do {
            observations = try await request.perform(on: imageData)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw ImageScanError.recognitionFailed
        }
        var seen: Set<String> = []
        return observations
            .compactMap(\.payloadString)
            .filter { !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) && seen.insert($0).inserted }
    }
}

private extension Character {
    nonisolated var isASCIIDigit: Bool { isASCII && isNumber }
}
