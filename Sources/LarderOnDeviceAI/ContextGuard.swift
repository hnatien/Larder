import Foundation

/// Decides whether a request fits the on-device context window, leaving room for the response.
nonisolated enum ContextGuard {
    /// The share of the context window a request may use; the rest is left for the response.
    static let budgetFraction = 0.7

    /// What to do with a request of a given size.
    enum Decision: Equatable, Sendable {
        /// The request fits the budget.
        case send
        /// The request is over budget but smaller than the whole window, so cutting the user text can make it fit.
        case truncate
        /// The request cannot be served on device.
        case reject
    }

    /// The decision for a request of `inputTokens` (instructions, schema and user text) in a window of `contextSize` tokens.
    static func decision(inputTokens: Int, contextSize: Int) -> Decision {
        guard contextSize > 0, inputTokens >= 0 else { return .reject }
        if inputTokens <= budget(contextSize: contextSize) { return .send }
        return inputTokens < contextSize ? .truncate : .reject
    }

    /// The user text to send, cut at a boundary when the route allows it, or `nil` when the request cannot be served on device.
    static func fit(_ text: String, textTokens: Int, overheadTokens: Int, contextSize: Int, allowsTruncation: Bool) -> String? {
        switch decision(inputTokens: textTokens + overheadTokens, contextSize: contextSize) {
        case .send:
            return text
        case .reject:
            return nil
        case .truncate:
            let allowedTextTokens = budget(contextSize: contextSize) - overheadTokens
            guard allowsTruncation, textTokens > 0, allowedTextTokens > 0 else { return nil }
            let maxCharacters = text.count * allowedTextTokens / textTokens
            let truncated = TextTruncator.truncate(text, maxCharacters: maxCharacters)
            return truncated.isEmpty ? nil : truncated
        }
    }

    /// The most tokens a request may use in a window of `contextSize` tokens.
    static func budget(contextSize: Int) -> Int {
        Int((Double(max(contextSize, 0)) * budgetFraction).rounded(.down))
    }

    /// A rough token count for SDKs without `tokenCount(for:)`: about three characters per token, rounded up.
    static func estimatedTokens(for text: String) -> Int {
        (text.count + 2) / 3
    }
}

/// Cuts text to a length, preferring the end of a sentence, then the end of a list entry, then a word.
nonisolated enum TextTruncator {
    /// The longest prefix of `text` with at most `maxCharacters` characters that ends at the best available boundary.
    static func truncate(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        guard maxCharacters > 0 else { return "" }
        let limit = text.index(text.startIndex, offsetBy: maxCharacters)
        let head = text[..<limit]

        var sentenceEnd: String.Index?
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .substringNotRequired]) { _, range, _, stop in
            if range.upperBound <= limit {
                sentenceEnd = range.upperBound
            } else {
                stop = true
            }
        }
        if let sentenceEnd, sentenceEnd > text.startIndex {
            return trimmed(text[..<sentenceEnd])
        }
        if let separator = head.lastIndex(where: { $0 == "," || $0 == ";" || $0.isNewline }) {
            return trimmed(head[..<separator])
        }
        if let space = head.lastIndex(where: \.isWhitespace) {
            return trimmed(head[..<space])
        }
        return String(head)
    }

    private static func trimmed(_ text: Substring) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
