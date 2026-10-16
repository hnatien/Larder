import Foundation
import LarderAssistant
import LarderCore

/// Maps an on-device pantry line to the Core type.
nonisolated enum PantryLineMapper {
    /// The Core line for `line`; the name is trimmed, quantities that are not positive and finite are dropped.
    ///
    /// `bestByHint` is not carried over: `ParsedPantryLine` has no best-by field yet.
    static func map(_ line: PantryLine) -> ParsedPantryLine {
        let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedPantryLine(
            rawText: name,
            name: name,
            quantity: line.quantity.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
            unit: UnitParser.unit(from: line.unit),
            location: StorageLocationMapper.location(from: line.location)
        )
    }
}

/// Maps loosely written storage words to a `StorageLocation`.
nonisolated enum StorageLocationMapper {
    /// The location `text` names, or `nil` when it names none.
    static func location(from text: String?) -> StorageLocation? {
        guard let text else { return nil }
        let key = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return table[key]
    }

    private static let table: [String: StorageLocation] = [
        "fridge": .fridge, "refrigerator": .fridge, "refrigerated": .fridge, "chiller": .fridge,
        "freezer": .freezer, "frozen": .freezer,
        "pantry": .pantry, "cupboard": .pantry, "larder": .pantry, "shelf": .pantry,
        "other": .other,
    ]
}

/// Maps an on-device recipe draft to the Core type.
nonisolated enum RecipeDraftMapper {
    /// The Core recipe for `draft`; counts and times that are not positive are dropped, as are empty ingredient names and steps.
    static func map(_ draft: RecipeDraft) -> ParsedRecipe {
        ParsedRecipe(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            servings: positive(draft.servings),
            prepMinutes: positive(draft.prepMinutes),
            cookMinutes: positive(draft.cookMinutes),
            ingredients: draft.ingredients.compactMap(ingredient),
            steps: draft.steps.compactMap(step)
        )
    }

    private static func ingredient(_ line: IngredientLine) -> ParsedIngredient? {
        let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let rawText = line.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedIngredient(
            rawText: rawText.isEmpty ? name : rawText,
            name: name,
            quantity: line.quantity.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
            unit: UnitParser.unit(from: line.unit)
        )
    }

    private static func step(_ line: StepLine) -> RecipeStep? {
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return RecipeStep(text: text, timerSeconds: positive(line.timerSeconds))
    }

    private static func positive(_ value: Int?) -> Int? {
        value.flatMap { $0 > 0 ? $0 : nil }
    }
}
