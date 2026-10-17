import Foundation

/// The language-model layer: explains, parses and proposes edits; never decides allergen safety.
///
/// Every request and response type here carries no personal identifiers: no names, emails,
/// locations, birth dates, exact weight, and no medical or religious constraints.
public protocol AssistantBackend: Sendable {
    /// Explains a solved plan from its reason codes.
    func explain(plan: PlanExplainRequest) async throws -> PlanExplanation
    /// Parses free text such as "2 onions, half a bag of rice" into pantry lines.
    func parsePantry(text: String) async throws -> [ParsedPantryLine]
    /// Parses a recipe from page text, a photo, or both.
    func parseRecipe(text: String, imageData: Data?) async throws -> ParsedRecipe
    /// Turns a conversational request into a constraint edit for the user to confirm.
    func adjust(request: AdjustRequest) async throws -> ConstraintEdit
}

/// A plan to explain. Carries no personal identifiers.
public struct PlanExplainRequest: Hashable, Codable, Sendable {
    public var meals: [Meal]
    /// Display names for foods referenced by reason codes.
    public var foodNames: [FoodID: String]

    /// Creates an explain request.
    public init(meals: [Meal], foodNames: [FoodID: String] = [:]) {
        self.meals = meals
        self.foodNames = foodNames
    }

    /// One meal of the plan, positioned by day offset from the plan start.
    public struct Meal: Hashable, Codable, Sendable {
        public var dayOffset: Int
        public var slot: MealType
        public var recipeTitle: String
        public var reasonCodes: [ReasonCode]

        /// Creates a meal summary.
        public init(dayOffset: Int, slot: MealType, recipeTitle: String, reasonCodes: [ReasonCode]) {
            self.dayOffset = dayOffset
            self.slot = slot
            self.recipeTitle = recipeTitle
            self.reasonCodes = reasonCodes
        }
    }
}

/// The assistant's explanation of a plan. Carries no personal identifiers.
public struct PlanExplanation: Hashable, Codable, Sendable {
    public var summary: String
    public var mealNotes: [MealNote]

    /// Creates an explanation.
    public init(summary: String, mealNotes: [MealNote]) {
        self.summary = summary
        self.mealNotes = mealNotes
    }

    /// A note for the meal at `mealIndex` in the request.
    public struct MealNote: Hashable, Codable, Sendable {
        public var mealIndex: Int
        public var text: String

        /// Creates a meal note.
        public init(mealIndex: Int, text: String) {
            self.mealIndex = mealIndex
            self.text = text
        }
    }
}

/// One pantry line parsed from free text. Carries no personal identifiers.
public struct ParsedPantryLine: Hashable, Codable, Sendable {
    public var rawText: String
    public var name: String
    public var quantity: Double?
    public var unit: UnitOfMeasure?
    public var location: StorageLocation?
    /// The start of the day the text says the item is best by, resolved from wording such as "exp friday"; `nil` when none is written.
    public var bestBy: Date?

    /// Creates a parsed pantry line.
    public init(
        rawText: String,
        name: String,
        quantity: Double? = nil,
        unit: UnitOfMeasure? = nil,
        location: StorageLocation? = nil,
        bestBy: Date? = nil
    ) {
        self.rawText = rawText
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.location = location
        self.bestBy = bestBy
    }
}

/// A recipe parsed from text or a photo, before food matching. Carries no personal identifiers.
public struct ParsedRecipe: Hashable, Codable, Sendable {
    public var title: String
    public var servings: Int?
    public var prepMinutes: Int?
    public var cookMinutes: Int?
    public var ingredients: [ParsedIngredient]
    public var steps: [RecipeStep]

    /// Creates a parsed recipe.
    public init(
        title: String,
        servings: Int? = nil,
        prepMinutes: Int? = nil,
        cookMinutes: Int? = nil,
        ingredients: [ParsedIngredient],
        steps: [RecipeStep]
    ) {
        self.title = title
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.ingredients = ingredients
        self.steps = steps
    }
}

/// One ingredient line parsed from a recipe. Carries no personal identifiers.
public struct ParsedIngredient: Hashable, Codable, Sendable {
    public var rawText: String
    public var name: String
    public var quantity: Double?
    public var unit: UnitOfMeasure?

    /// Creates a parsed ingredient line.
    public init(rawText: String, name: String, quantity: Double? = nil, unit: UnitOfMeasure? = nil) {
        self.rawText = rawText
        self.name = name
        self.quantity = quantity
        self.unit = unit
    }
}

/// A conversational adjustment with non-sensitive context only. Carries no personal identifiers.
public struct AdjustRequest: Hashable, Codable, Sendable {
    /// The user's request, scrubbed on device before it is sent.
    public var message: String
    public var maxCookMinutes: Int
    public var dietPatterns: Set<DietPattern>
    public var goal: Goal

    /// Creates an adjust request.
    public init(message: String, maxCookMinutes: Int, dietPatterns: Set<DietPattern>, goal: Goal) {
        self.message = message
        self.maxCookMinutes = maxCookMinutes
        self.dietPatterns = dietPatterns
        self.goal = goal
    }
}

/// Proposed constraint changes; re-verified and confirmed by the user before they apply. Carries no personal identifiers.
public struct ConstraintEdit: Hashable, Codable, Sendable {
    public var changes: [Change]
    /// A one-line description shown when asking the user to confirm.
    public var summary: String
    /// A question the assistant asks back when the request was unclear or asked for something it cannot change here.
    public var clarifyingQuestion: String?
    /// How many proposed edits were left out because a request cannot make them, such as allergen, medical or religious ones.
    public var droppedCount: Int

    /// Creates a constraint edit.
    public init(changes: [Change], summary: String, clarifyingQuestion: String? = nil, droppedCount: Int = 0) {
        self.changes = changes
        self.summary = summary
        self.clarifyingQuestion = clarifyingQuestion
        self.droppedCount = droppedCount
    }

    /// One proposed change; `dayOffset` limits it to one day of the plan, `nil` means the whole plan.
    public enum Change: Hashable, Codable, Sendable {
        case addDiet(DietPattern, dayOffset: Int?)
        case removeDiet(DietPattern)
        case setMaxCookMinutes(Int, dayOffset: Int?)
        case addDislike(String)
        case removeDislike(String)
        case useUp(String)
    }
}
