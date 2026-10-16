import Foundation

/// Resolves an ingredient line to grams, shared by nutrition and grocery maths.
enum IngredientGrams {
    /// `gramsResolved` when valid, else a conversion using the food's density and best-matching portion; `nil` when neither works.
    static func resolve(_ ingredient: Ingredient, food: Food?) -> Double? {
        if let grams = ingredient.gramsResolved, grams.isFinite, grams >= 0 {
            return grams
        }
        return try? UnitConverter.grams(
            from: ingredient.quantity,
            unit: ingredient.unit,
            density: food?.densityGPerMl,
            portion: food.flatMap { portion(for: ingredient.unit, in: $0) }
        )
    }

    /// For a count unit, the portion whose label names the unit ("1 clove" for `.clove`), else the first portion.
    static func portion(for unit: UnitOfMeasure, in food: Food) -> Portion? {
        guard unit.isCount else { return nil }
        return food.portions.first { TermMatcher.contains(unit.rawValue, in: TermMatcher.words($0.label)) }
            ?? food.portions.first
    }
}
