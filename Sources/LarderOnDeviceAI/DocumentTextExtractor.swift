import Foundation
import Vision

/// Reads the printed text of a photographed document, such as a receipt or a recipe card, on device.
public nonisolated struct DocumentTextExtractor: Sendable {
    /// Creates an extractor.
    public init() {}

    /// The text lines in `imageData`, top to bottom and left to right; fragments printed on one row form one line.
    ///
    /// Uses `RecognizeDocumentsRequest`, falling back to `RecognizeTextRequest` where the document request is unsupported.
    public func lines(in imageData: Data) async throws -> [String] {
        try ImageDataValidator.validate(imageData)
        do {
            return ReadingOrder.lines(from: try await observations(in: imageData).map(TextFragment.init))
        } catch let error as CancellationError {
            throw error
        } catch {
            throw ImageScanError.recognitionFailed
        }
    }

    private func observations(in imageData: Data) async throws -> [RecognizedTextObservation] {
        if !RecognizeDocumentsRequest.supportedRevisions.isEmpty {
            do {
                return try await RecognizeDocumentsRequest().perform(on: imageData).flatMap(\.document.text.lines)
            } catch let error as VisionError where Self.meansUnsupported(error) {
                return try await RecognizeTextRequest().perform(on: imageData)
            }
        }
        return try await RecognizeTextRequest().perform(on: imageData)
    }

    private static func meansUnsupported(_ error: VisionError) -> Bool {
        switch error {
        case .unsupportedRequest, .unsupportedRevision, .unsupportedComputeDevice, .unsupportedComputeStage: true
        default: false
        }
    }
}

/// A recognised piece of text and where it sits, in Vision's normalised coordinates (origin at the bottom left).
nonisolated struct TextFragment: Equatable, Sendable {
    var text: String
    var minX: Double
    var midY: Double
    var height: Double
}

nonisolated extension TextFragment {
    init(_ observation: RecognizedTextObservation) {
        let box = observation.boundingBox
        self.init(
            text: observation.topCandidates(1).first?.string ?? "",
            minX: Double(box.origin.x),
            midY: Double(box.origin.y + box.height / 2),
            height: Double(box.height)
        )
    }
}

/// Arranges recognised fragments into printed lines.
nonisolated enum ReadingOrder {
    /// Rows top to bottom, each row's fragments left to right joined by a space; fragments whose centres sit within
    /// half a line height of a row's first fragment belong to that row. Empty fragments are dropped.
    static func lines(from fragments: [TextFragment]) -> [String] {
        var rows: [[TextFragment]] = []
        let ordered = fragments
            .map { TextFragment(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), minX: $0.minX, midY: $0.midY, height: $0.height) }
            .filter { !$0.text.isEmpty }
            .sorted { $0.midY > $1.midY }
        for fragment in ordered {
            if let anchor = rows.last?.first, abs(anchor.midY - fragment.midY) <= max(anchor.height, fragment.height) / 2 {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { row in row.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ") }
    }
}
