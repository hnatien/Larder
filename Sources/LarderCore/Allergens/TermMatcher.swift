import Foundation

/// Whole-word, case- and diacritic-insensitive matching of short terms against ingredient text.
enum TermMatcher {
    /// Lowercased words of `text`; apostrophes are dropped so "za'atar" reads as "zaatar".
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacing("'", with: "")
            .replacing("\u{2019}", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Whether `term` appears in `words` as whole words, allowing a plural on each word.
    ///
    /// A match directly followed by "free" ("gluten-free", "nut free") is a claim of absence and does not count,
    /// nor does a match that overlaps any of the `excluded` word ranges.
    static func contains(_ term: String, in words: [String], excluding excluded: [Range<Int>] = []) -> Bool {
        occurrences(of: term, in: words).contains { range in
            let freeClaim = range.upperBound < words.count && words[range.upperBound] == "free"
            return !freeClaim && !excluded.contains { $0.overlaps(range) }
        }
    }

    /// The first of `terms` found in `text`, trying longer terms first so evidence names the most specific term.
    ///
    /// An occurrence inside one of the `exceptions` phrases ("butter" in "peanut butter") does not count; other
    /// occurrences in the same text still do.
    static func firstMatch(of terms: [String], in text: String, except exceptions: [String] = []) -> String? {
        let textWords = words(text)
        let excluded = exceptions.flatMap { occurrences(of: $0, in: textWords) }
        return terms.sorted { $0.count > $1.count }.first { contains($0, in: textWords, excluding: excluded) }
    }

    /// Word ranges where `term` appears in `words` as whole words, allowing a plural on each word.
    private static func occurrences(of term: String, in words: [String]) -> [Range<Int>] {
        let termWords = Self.words(term)
        guard !termWords.isEmpty, words.count >= termWords.count else { return [] }
        return (0...(words.count - termWords.count)).compactMap { start in
            let range = start..<(start + termWords.count)
            return zip(words[range], termWords).allSatisfy({ isForm($0, of: $1) }) ? range : nil
        }
    }

    private static func isForm(_ word: String, of base: String) -> Bool {
        if word == base || word == base + "s" || word == base + "es" { return true }
        return base.hasSuffix("y") && word == base.dropLast() + "ies"
    }
}
