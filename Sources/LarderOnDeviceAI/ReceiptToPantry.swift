import Foundation
import LarderCore

/// Turns a receipt photo into draft pantry lines for the user to confirm.
public nonisolated enum ReceiptToPantry {
    /// Reads the receipt's text on device, keeps the product lines and asks `assistant` to parse them.
    public static func parse(imageData: Data, assistant: any AssistantBackend) async throws -> [ParsedPantryLine] {
        try await parse(lines: DocumentTextExtractor().lines(in: imageData), assistant: assistant)
    }

    static func parse(lines: [String], assistant: any AssistantBackend) async throws -> [ParsedPantryLine] {
        let candidates = ReceiptLineFilter.pantryCandidates(from: lines)
        guard !candidates.isEmpty else { return [] }
        return try await assistant.parsePantry(text: candidates.joined(separator: ", "))
    }
}
