import Foundation
import LarderCore

/// Maps loosely written unit words such as "tbsp", "Grams" or "fl oz" to a `UnitOfMeasure`.
public enum UnitParser {
    /// The unit `text` names, or `nil` when it names none.
    public static func unit(from text: String?) -> UnitOfMeasure? {
        guard let text else { return nil }
        let key = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return table[key]
    }

    private static let table: [String: UnitOfMeasure] = {
        let spellings: [UnitOfMeasure: [String]] = [
            .gram: ["g", "gr", "gram", "grams", "gramme", "grammes"],
            .kilogram: ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms", "kilogramme", "kilogrammes"],
            .milligram: ["mg", "milligram", "milligrams"],
            .millilitre: ["ml", "millilitre", "millilitres", "milliliter", "milliliters"],
            .litre: ["l", "litre", "litres", "liter", "liters"],
            .teaspoon: ["tsp", "tsps", "teaspoon", "teaspoons"],
            .tablespoon: ["tbsp", "tbsps", "tbs", "tbl", "tablespoon", "tablespoons"],
            .cup: ["cup", "cups"],
            .fluidOunce: ["fl oz", "floz", "fluid ounce", "fluid ounces"],
            .ounce: ["oz", "ounce", "ounces"],
            .pound: ["lb", "lbs", "pound", "pounds"],
            .piece: ["piece", "pieces", "pc", "pcs"],
            .pinch: ["pinch", "pinches"],
            .clove: ["clove", "cloves"],
            .slice: ["slice", "slices"],
        ]
        var table: [String: UnitOfMeasure] = [:]
        for (unit, words) in spellings {
            for word in words {
                table[word] = unit
            }
        }
        return table
    }()
}
