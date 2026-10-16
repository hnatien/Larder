import Foundation

/// The share of a day's eating each meal type carries, used to scale per-day targets to the slots a plan covers.
public enum MealSlotShare {
    /// The fraction of a day's intake that `type` carries; the four shares sum to 1.
    public static func share(of type: MealType) -> Double {
        Double(percent(of: type)) / 100
    }

    /// The fraction of a day's intake that `slots` cover together: 0.35 for dinners only, exactly 1 for all four.
    public static func coverage(slots: Set<MealType>) -> Double {
        Double(slots.reduce(0) { $0 + percent(of: $1) }) / 100
    }

    /// Whole percentages keep sums exact and independent of set order.
    private static func percent(of type: MealType) -> Int {
        switch type {
        case .breakfast: 25
        case .lunch: 30
        case .dinner: 35
        case .snack: 10
        }
    }
}
