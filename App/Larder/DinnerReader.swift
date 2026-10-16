import Foundation
import LarderCore

/// Reads planned dinners from the active plan, for the widget snapshot and App Intents.
nonisolated struct DinnerReader: Sendable {
    let plans: any PlanRepository
    let recipes: any RecipeRepository
    let calendar: Calendar

    /// Dinners of the active plan on or after the day containing `date`, in date order; skipped meals are left out.
    func dinners(from date: Date) async throws -> [TodaySnapshot.Dinner] {
        guard let plan = try await plans.currentPlan() else { return [] }
        let today = calendar.startOfDay(for: date)
        let meals = try await plans.meals(for: plan.id)
            .filter { $0.slot == .dinner && $0.status != .skipped && calendar.startOfDay(for: $0.date) >= today }
            .sorted { $0.date < $1.date }
        var dinners: [TodaySnapshot.Dinner] = []
        for meal in meals {
            guard let recipe = try await recipes.recipe(by: meal.recipeID) else { continue }
            dinners.append(TodaySnapshot.Dinner(
                day: calendar.startOfDay(for: meal.date),
                title: recipe.title,
                minutes: recipe.prepMinutes + recipe.cookMinutes
            ))
        }
        return dinners
    }

    /// Tonight's dinner, if one is planned.
    func tonight(at date: Date) async throws -> TodaySnapshot.Dinner? {
        try await dinners(from: date).first { calendar.isDate($0.day, inSameDayAs: date) }
    }
}
