import Foundation
import LarderCore

/// An ingredient line split into amount, unit and name.
nonisolated struct ParsedIngredientLine: Hashable, Sendable {
    var quantity: Double?
    var unit: UnitOfMeasure?
    var name: String
    var isOptional: Bool
}

/// A lenient parser for free-text ingredient lines such as "1 (400 g) can chickpeas, drained".
nonisolated enum IngredientLineParser {
    private static let unitWords: [String: UnitOfMeasure] = [
        "g": .gram, "gram": .gram, "grams": .gram, "gm": .gram,
        "kg": .kilogram, "kilogram": .kilogram, "kilograms": .kilogram,
        "mg": .milligram, "milligram": .milligram, "milligrams": .milligram,
        "ml": .millilitre, "millilitre": .millilitre, "millilitres": .millilitre,
        "milliliter": .millilitre, "milliliters": .millilitre,
        "l": .litre, "litre": .litre, "litres": .litre, "liter": .litre, "liters": .litre,
        "tsp": .teaspoon, "tsps": .teaspoon, "teaspoon": .teaspoon, "teaspoons": .teaspoon,
        "tbsp": .tablespoon, "tbsps": .tablespoon, "tbs": .tablespoon, "tablespoon": .tablespoon, "tablespoons": .tablespoon,
        "cup": .cup, "cups": .cup, "c": .cup,
        "oz": .ounce, "ounce": .ounce, "ounces": .ounce,
        "lb": .pound, "lbs": .pound, "pound": .pound, "pounds": .pound,
        "pinch": .pinch, "pinches": .pinch, "dash": .pinch, "dashes": .pinch,
        "clove": .clove, "cloves": .clove,
        "slice": .slice, "slices": .slice,
        "piece": .piece, "pieces": .piece,
    ]

    private static let containerWords: Set<String> = ["can", "cans", "tin", "tins", "jar", "jars", "packet", "packets", "package", "packages"]
    private static let indefiniteWords: Set<String> = ["little", "few", "bit", "splash", "drizzle", "sprinkle", "touch", "couple"]
    private static let fluidOunceWords = ["fluid ounces", "fluid ounce", "fl. oz.", "fl. oz", "fl oz"]
    private static let trailingNotes = ["or to taste", "to taste", "as needed", "for serving", "for garnish"]

    /// Splits `line`; an unreadable amount leaves `quantity` and `unit` nil and the whole line as the name.
    static func parse(_ line: String) -> ParsedIngredientLine {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        text = String(text.drop { $0 == "-" || $0 == "\u{2022}" || $0 == "*" || $0 == " " })
        var isOptional = false
        if let stripped = removingOptional(from: text) {
            text = stripped
            isOptional = true
        }

        var rest = Substring(text)
        var quantity: Double?
        var unit: UnitOfMeasure?

        if let amount = QuantityText.scan(rest) {
            quantity = amount.value
            rest = rest[amount.end...].drop { $0 == " " }
            if let measure = parenthesisedMeasure(rest) {
                quantity = (quantity ?? 1) * measure.quantity
                unit = measure.unit
                rest = measure.rest
                rest = dropContainerWord(rest)
            } else if let found = unitPrefix(of: rest) {
                unit = found.unit
                rest = found.rest
                rest = rest.drop { $0 == " " }
                if let measure = parenthesisedMeasure(rest) { rest = measure.rest }
            } else {
                rest = dropContainerWord(rest)
            }
        } else if let article = articleQuantity(rest) {
            quantity = 1
            unit = article.unit
            rest = article.rest
        }

        var name = String(rest)
        for note in trailingNotes {
            if let range = name.range(of: note, options: [.caseInsensitive, .backwards]), name[range.upperBound...].allSatisfy({ !$0.isLetter }) {
                name.removeSubrange(range.lowerBound...)
                break
            }
        }
        if name.lowercased().hasPrefix("of ") { name = String(name.dropFirst(3)) }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.-").union(.whitespacesAndNewlines))
        return ParsedIngredientLine(quantity: quantity, unit: unit, name: name.isEmpty ? text : name, isOptional: isOptional)
    }

    /// The unit named at the start of `text`, such as "cups flour" or "g flour".
    static func unit(at text: Substring) -> UnitOfMeasure? {
        unitPrefix(of: text.drop { $0 == " " })?.unit
    }

    private static func removingOptional(from text: String) -> String? {
        guard text.range(of: "optional", options: .caseInsensitive) != nil else { return nil }
        var result = text
        for pattern in ["(optional)", ", optional", "optional:", "optional"] {
            if let range = result.range(of: pattern, options: .caseInsensitive) {
                result.removeSubrange(range)
                break
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:").union(.whitespacesAndNewlines))
    }

    private static func unitPrefix(of text: Substring) -> (unit: UnitOfMeasure, rest: Substring)? {
        let lowered = text.lowercased()
        if let prefix = fluidOunceWords.first(where: { lowered.hasPrefix($0) }) {
            return (.fluidOunce, text.dropFirst(prefix.count).drop { $0 == " " })
        }
        var end = text.startIndex
        while end < text.endIndex, text[end].isLetter { end = text.index(after: end) }
        guard end > text.startIndex, let unit = unitWords[text[text.startIndex..<end].lowercased()] else { return nil }
        var rest = text[end...]
        if rest.first == "." { rest = rest.dropFirst() }
        rest = rest.drop { $0 == " " }
        if rest.lowercased().hasPrefix("of ") { rest = rest.dropFirst(3) }
        return (unit, rest)
    }

    private static func parenthesisedMeasure(_ text: Substring) -> (quantity: Double, unit: UnitOfMeasure, rest: Substring)? {
        guard text.first == "(", let close = text.firstIndex(of: ")") else { return nil }
        let inner = text[text.index(after: text.startIndex)..<close]
        guard let amount = QuantityText.scan(inner),
              let found = unitPrefix(of: inner[amount.end...].drop { $0 == " " })
        else { return nil }
        return (amount.value, found.unit, text[text.index(after: close)...].drop { $0 == " " })
    }

    private static func dropContainerWord(_ text: Substring) -> Substring {
        var end = text.startIndex
        while end < text.endIndex, text[end].isLetter { end = text.index(after: end) }
        guard containerWords.contains(text[text.startIndex..<end].lowercased()) else { return text }
        return text[end...].drop { $0 == " " }
    }

    private static func articleQuantity(_ text: Substring) -> (unit: UnitOfMeasure?, rest: Substring)? {
        let lowered = text.lowercased()
        guard lowered.hasPrefix("a ") || lowered.hasPrefix("an ") else { return nil }
        let afterArticle = text.drop { $0 != " " }.drop { $0 == " " }
        let nextWord = afterArticle.prefix { $0.isLetter }.lowercased()
        guard !indefiniteWords.contains(nextWord) else { return nil }
        if let found = unitPrefix(of: afterArticle) { return (found.unit, found.rest) }
        return (nil, afterArticle)
    }
}
