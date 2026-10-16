import Foundation

/// Turns user search text into FTS5 and LIKE patterns.
enum SearchText {
    /// An FTS5 query matching every token of `text` as a prefix, or `nil` when `text` has no letters or digits.
    ///
    /// Each token is quoted, so FTS5 operators typed by the user (`AND`, `NEAR`, `-`, `"`) are matched as text.
    static func prefixPattern(for text: String) -> String? {
        let tokens = text.split { !($0.isLetter || $0.isNumber) }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    /// A `LIKE` pattern matching `text` anywhere, with `\` escaping the wildcards.
    static func likePattern(for text: String) -> String {
        let escaped = text
            .replacing("\\", with: "\\\\")
            .replacing("%", with: "\\%")
            .replacing("_", with: "\\_")
        return "%\(escaped)%"
    }

    /// The escape character used by `likePattern(for:)`.
    static let likeEscape = "\\"
}
