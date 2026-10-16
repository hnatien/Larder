import FoundationModels

/// The pantry lines the on-device model extracts from free text.
@Generable
nonisolated struct PantryLines: Equatable {
    @Guide(description: "One entry per food item mentioned, in the order written. Empty when the text names no food.")
    var lines: [PantryLine]
}

/// One pantry item as the on-device model extracted it.
@Generable
nonisolated struct PantryLine: Equatable {
    @Guide(description: "The food name as written, without quantity, unit or storage place.")
    var name: String
    @Guide(description: "The amount as a number when one is written, such as 2 for \"two\" or 0.5 for \"half\"; null when none is written.")
    var quantity: Double?
    @Guide(description: "The unit or container word exactly as written, such as \"g\", \"cups\" or \"bag\"; null when none is written.")
    var unit: String?
    @Guide(description: "Where the item is kept, only when the text says so.", .anyOf(PantryLocationHint.allowedValues))
    var location: String?
    @Guide(description: "A best-by or use-by date phrase exactly as written; null when none is written.")
    var bestByHint: String?
}

/// A recipe as the on-device model extracted it from page text.
@Generable
nonisolated struct RecipeDraft: Equatable {
    @Guide(description: "The recipe title as written.")
    var title: String
    @Guide(description: "The number of servings when written; null otherwise.")
    var servings: Int?
    @Guide(description: "Preparation time in minutes when written; null otherwise.")
    var prepMinutes: Int?
    @Guide(description: "Cooking time in minutes when written; null otherwise.")
    var cookMinutes: Int?
    @Guide(description: "Every ingredient line, in the order written.")
    var ingredients: [IngredientLine]
    @Guide(description: "Every method step, in the order written.")
    var steps: [StepLine]
}

/// One recipe ingredient as the on-device model extracted it.
@Generable
nonisolated struct IngredientLine: Equatable {
    @Guide(description: "The whole ingredient line exactly as written.")
    var rawText: String
    @Guide(description: "The ingredient name without quantity or unit.")
    var name: String
    @Guide(description: "The amount as a number when written; null otherwise.")
    var quantity: Double?
    @Guide(description: "The unit exactly as written, such as \"tbsp\" or \"g\"; null when none is written.")
    var unit: String?
}

/// One recipe step as the on-device model extracted it.
@Generable
nonisolated struct StepLine: Equatable {
    @Guide(description: "The step text as written.")
    var text: String
    @Guide(description: "The duration the step names, in seconds, such as 600 for \"10 minutes\"; null when it names none.")
    var timerSeconds: Int?
}

/// The storage words the pantry schema allows the model to emit.
nonisolated enum PantryLocationHint {
    static let allowedValues = ["fridge", "freezer", "pantry", "other"]
}
