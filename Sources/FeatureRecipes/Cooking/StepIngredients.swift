import LarderCore

/// Finds the ingredients a step talks about.
nonisolated enum StepIngredients {
    private static let shortestTerm = 3

    /// Ingredients whose name, or its last word, appears as whole words in `stepText`, in recipe order.
    static func matching(_ stepText: String, in ingredients: [Ingredient]) -> [Ingredient] {
        let stepWords = WordForms.words(stepText).map(WordForms.singular)
        return ingredients.filter { ingredient in
            let name = IngredientLineParser.parse(ingredient.rawText).name
            let phrase = WordForms.words(name.split(separator: ",").first.map(String.init) ?? name).map(WordForms.singular)
            guard let last = phrase.last, last.count >= shortestTerm else { return false }
            return contains(phrase, in: stepWords) || stepWords.contains(last)
        }
    }

    /// One line listing the matching ingredients as written, or `nil` when the step names none.
    static func summary(for stepText: String, in ingredients: [Ingredient]) -> String? {
        let matches = matching(stepText, in: ingredients)
        return matches.isEmpty ? nil : matches.map(\.rawText).joined(separator: "; ")
    }

    private static func contains(_ phrase: [String], in words: [String]) -> Bool {
        guard !phrase.isEmpty, words.count >= phrase.count else { return false }
        return (0...(words.count - phrase.count)).contains { Array(words[$0..<($0 + phrase.count)]) == phrase }
    }
}
