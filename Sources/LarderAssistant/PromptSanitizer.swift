import Foundation

/// Removes contact details and card numbers from user text before it leaves the device, and trims it to the proxy's limits.
public struct PromptSanitizer: Sendable {
    /// Replaces each removed span.
    public static let removedToken = "[removed]"

    public var pantryLimit: Int
    public var recipeLimit: Int
    public var instructionLimit: Int

    /// Creates a sanitizer; limits count UTF-16 code units, as the proxy does.
    public init(pantryLimit: Int = 500, recipeLimit: Int = 20_000, instructionLimit: Int = 300) {
        self.pantryLimit = pantryLimit
        self.recipeLimit = recipeLimit
        self.instructionLimit = instructionLimit
    }

    /// Replaces emails, URLs, 16-digit card-like numbers and phone numbers with `removedToken`.
    public func scrub(_ text: String) -> String {
        text
            .replacing(#/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/#, with: Self.removedToken)
            .replacing(#/(?i)\b(?:https?://|www\.)\S+/#, with: Self.removedToken)
            .replacing(#/\b\d(?:[ \-]?\d){15}\b/#, with: Self.removedToken)
            .replacing(#/\+?\(?\d[\d\s().\-]{5,18}\d/#) { match in
                Self.isPhoneNumber(match.output) ? Substring(Self.removedToken) : match.output
            }
    }

    /// Scrubs `text`, trims surrounding whitespace, and cuts it to at most `limit` UTF-16 code units without splitting a character.
    public func scrub(_ text: String, limit: Int) -> String {
        var result = ""
        var length = 0
        for character in scrub(text).trimmingCharacters(in: .whitespacesAndNewlines) {
            length += character.utf16.count
            guard length <= limit else { break }
            result.append(character)
        }
        return result
    }

    private static func isPhoneNumber(_ candidate: Substring) -> Bool {
        let digits = candidate.count(where: \.isNumber)
        let minimum = candidate.hasPrefix("+") ? 7 : 9
        return (minimum...15).contains(digits)
    }
}
