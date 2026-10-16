/// Crude English singularising, enough to match "eggs" with "egg" and "olives" with "olive".
nonisolated enum WordForms {
    /// `word`, lowercased, without a plural ending.
    static func singular(_ word: String) -> String {
        let word = word.lowercased()
        if word.hasSuffix("ies"), word.count > 4 { return word.dropLast(3) + "y" }
        if ["oes", "ses", "xes", "ches", "shes"].contains(where: word.hasSuffix) { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }

    /// Lowercased letter-only words of `text`.
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init)
    }
}
