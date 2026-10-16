import LarderCore

/// Scales ingredient amounts to a different number of servings, rounded to amounts a cook can measure.
nonisolated enum IngredientScaler {
    /// `ingredients` for `target` servings instead of `source`; unchanged when either count is not positive.
    static func scale(ingredients: [Ingredient], from source: Int, to target: Int) -> [Ingredient] {
        guard source > 0, target > 0, source != target else { return ingredients }
        let factor = Double(target) / Double(source)
        return ingredients.map { ingredient in
            var scaled = ingredient
            scaled.quantity = ingredient.quantity > 0 ? rounded(ingredient.quantity * factor, unit: ingredient.unit) : 0
            scaled.gramsResolved = ingredient.gramsResolved.map { $0 * factor }
            scaled.rawText = scaledText(ingredient.rawText, factor: factor)
            return scaled
        }
    }

    /// `value` rounded for `unit`: grams and millilitres to 5 from 50 up and to 0.5 below, everything else to 0.25.
    /// A positive value never rounds down to zero.
    static func rounded(_ value: Double, unit: UnitOfMeasure) -> Double {
        let step: Double = switch unit {
        case .gram, .millilitre: value >= 50 ? 5 : 0.5
        case .milligram: 0.5
        default: 0.25
        }
        guard value > 0 else { return value }
        return max((value / step).rounded() * step, step)
    }

    /// `text` with its leading amount multiplied by `factor`; text without a leading amount is returned as written.
    private static func scaledText(_ text: String, factor: Double) -> String {
        let trimmed = Substring(text).drop { $0 == " " }
        guard let amount = QuantityText.scan(trimmed) else { return text }
        let unit = IngredientLineParser.unit(at: trimmed[amount.end...]) ?? .piece
        var scaled = QuantityText.format(rounded(amount.lower * factor, unit: unit))
        if let upper = amount.upper {
            scaled += "-" + QuantityText.format(rounded(upper * factor, unit: unit))
        }
        return scaled + trimmed[amount.end...]
    }
}
