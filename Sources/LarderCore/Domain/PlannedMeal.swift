import Foundation

/// One recipe placed in a plan slot, with the reasons it was chosen.
public struct PlannedMeal: Identifiable, Hashable, Codable, Sendable {
    public var id: PlannedMealID
    public var planID: MealPlanID
    public var date: Date
    public var slot: MealType
    public var recipeID: RecipeID
    public var servings: Int
    public var leftoverOf: PlannedMealID?
    public var isLocked: Bool
    public var status: MealStatus
    public var reasonCodes: [ReasonCode]
    /// Recipes previously in this slot, oldest first.
    public var swapHistory: [RecipeID]

    /// Creates a planned meal.
    public init(
        id: PlannedMealID = PlannedMealID(),
        planID: MealPlanID,
        date: Date,
        slot: MealType,
        recipeID: RecipeID,
        servings: Int,
        leftoverOf: PlannedMealID? = nil,
        isLocked: Bool = false,
        status: MealStatus = .planned,
        reasonCodes: [ReasonCode] = [],
        swapHistory: [RecipeID] = []
    ) {
        self.id = id
        self.planID = planID
        self.date = date
        self.slot = slot
        self.recipeID = recipeID
        self.servings = servings
        self.leftoverOf = leftoverOf
        self.isLocked = isLocked
        self.status = status
        self.reasonCodes = reasonCodes
        self.swapHistory = swapHistory
    }
}

/// What happened to a planned meal.
public enum MealStatus: String, CaseIterable, Hashable, Codable, Sendable {
    case planned
    case cooked
    case skipped
}
