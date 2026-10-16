import Foundation
import LarderCore

/// Parses pantry text such as "2 onions, half a bag of rice in the pantry" with fixed rules; works fully offline.
public struct DeterministicPantryParser: Sendable {
    /// Creates a parser.
    public init() {}

    /// One line per comma, semicolon or newline separated entry; entries with no food name are skipped.
    public func parse(_ text: String) -> [ParsedPantryLine] {
        text
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .compactMap { parseLine($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func parseLine(_ rawText: String) -> ParsedPantryLine? {
        guard !rawText.isEmpty else { return nil }
        var remainder = Substring(rawText)
        var location: StorageLocation?
        if let match = remainder.firstMatch(of: Self.locationPattern) {
            location = Self.location(named: match.output.1.lowercased())
            remainder.removeSubrange(match.range)
        }

        var words = remainder.split(whereSeparator: \.isWhitespace).map(String.init)
        var quantity = leadingQuantity(&words)
        var unit: UnitOfMeasure?
        if quantity == nil, let first = words.first, let (number, suffix) = Self.splitAttachedUnit(first) {
            quantity = number
            unit = suffix
            words.removeFirst()
        }
        if quantity != nil, unit == nil {
            if words.count >= 2, let twoWordUnit = UnitParser.unit(from: "\(words[0]) \(words[1])") {
                unit = twoWordUnit
                words.removeFirst(2)
            } else if let first = words.first, let oneWordUnit = UnitParser.unit(from: first) {
                unit = oneWordUnit
                words.removeFirst()
            }
        }
        if unit != nil, words.first?.lowercased() == "of" {
            words.removeFirst()
        }
        let name = words.joined(separator: " ")
        guard !name.isEmpty else { return nil }
        return ParsedPantryLine(rawText: rawText, name: name, quantity: quantity, unit: unit, location: location)
    }

    private func leadingQuantity(_ words: inout [String]) -> Double? {
        guard let first = words.first?.lowercased() else { return nil }
        let second = words.dropFirst().first?.lowercased()
        var quantity: Double
        if first == "half", second == "a" || second == "an" {
            quantity = 0.5
            words.removeFirst(2)
        } else if first == "a" || first == "an", second == "dozen" {
            quantity = 12
            words.removeFirst(2)
            return quantity
        } else if first == "dozen" {
            words.removeFirst()
            return 12
        } else if first == "a" || first == "an" {
            quantity = 1
            words.removeFirst()
        } else if let number = Self.number(first) {
            quantity = number
            words.removeFirst()
            if let next = words.first, let fraction = Self.fraction(next), fraction < 1, !first.contains("/") {
                quantity += fraction
                words.removeFirst()
            }
        } else {
            return nil
        }
        if words.first?.lowercased() == "dozen" {
            quantity *= 12
            words.removeFirst()
        }
        return quantity
    }

    private static var locationPattern: Regex<(Substring, Substring)> {
        #/(?i)\s*\b(?:(?:in|into|from)\s+)?(?:(?:the|my)\s+)?(freezer|fridge|refrigerator|pantry|cupboard)\b/#
    }

    private static func location(named word: String) -> StorageLocation {
        switch word {
        case "freezer": .freezer
        case "fridge", "refrigerator": .fridge
        default: .pantry
        }
    }

    private static func number(_ word: String) -> Double? {
        fraction(word) ?? Double(word).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    private static func fraction(_ word: String) -> Double? {
        let parts = word.split(separator: "/")
        guard parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator > 0 else {
            return nil
        }
        return numerator / denominator
    }

    private static func splitAttachedUnit(_ word: String) -> (Double, UnitOfMeasure)? {
        guard let match = word.wholeMatch(of: #/(\d+(?:\.\d+)?)([A-Za-z]+)/#),
              let number = Double(match.output.1),
              let unit = UnitParser.unit(from: String(match.output.2))
        else { return nil }
        return (number, unit)
    }
}
