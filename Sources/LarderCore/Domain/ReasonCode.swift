import Foundation

/// A structured reason the planner chose a meal; the UI and assistant turn these into copy.
public enum ReasonCode: Hashable, Codable, Sendable {
    case usesExpiring(food: FoodID, bestBy: Date)
    case pantryOverlap(count: Int)
    case quick(minutes: Int)
    case fibreGap(gramsShort: Double)
    case varietyCuisine(cuisine: String)
    case leftoverOf(meal: PlannedMealID)
    case underBudget
    /// The household cooks a lot of this cuisine.
    case cooksOften(cuisine: String)
    /// The household cooks a lot with this food.
    case cooksOftenWith(food: FoodID)
}
