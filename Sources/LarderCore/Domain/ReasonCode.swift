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
    /// A plan repair moved the meal here from the day it was first planned on.
    case movedFrom(date: Date)
    /// A plan repair put this recipe in the slot in place of what was there.
    case replacedBecause(cause: RepairCause)
}

/// Why a plan repair changed a meal.
public enum RepairCause: Hashable, Codable, Sendable {
    /// The meal it depended on was skipped.
    case skipped
    /// A meal from an earlier day was never cooked.
    case notCooked
    /// A food the meal counted on is no longer on the shelves.
    case outOfStock(food: FoodID)
    /// A food the meal counted on passed its best-by date.
    case expired(food: FoodID)
    /// The swap brings the week back inside a nutrient band the deviation pushed it out of.
    case balance
}
