import Foundation
import LarderCore

/// A week planned with an assistant adjustment, and the days whose own rule could not be met.
public nonisolated struct AdjustedWeek: Sendable {
    public var result: PlanResult
    /// Offsets from the plan start of days whose rule no recipe met, so they keep the planner's pick.
    public var unmetDayOffsets: [Int]
}

nonisolated extension PlanningService {
    /// Solves a week from `startDate` under `adjustment`: week-wide rules join the stored ones for the whole solve,
    /// then each day with a rule of its own gets the best admitted swap for any meal that misses it.
    ///
    /// Locked meals are never changed. The result is verified against the stored constraints, which every meal
    /// still meets because an adjustment only adds rules.
    public func planWeek(
        startDate: Date,
        slots: [MealType] = [.dinner],
        seed: UInt64,
        locked: [PlannedMeal],
        adjustment: WeekAdjustment
    ) async throws -> AdjustedWeek {
        let catalogue = try await catalogue()
        var inputs = try await inputs(catalogue: catalogue)
        let stored = inputs.compiled
        inputs.compiled.constraints = adjustment.constraints(adding: stored.constraints, at: dates.now)
        if let minutes = adjustment.maxCookMinutes {
            inputs.compiled.maxCookMinutes = minutes
            inputs.context.maxCookMinutes = minutes
        }
        inputs.context.useUp = adjustment.useUpFoods(in: inputs.context.pantry, foods: catalogue.foods)

        var result = WeekPlanner.plan(
            PlanRequest(
                startDate: startDate,
                days: Self.weekDays,
                slots: slots,
                candidates: catalogue.candidates,
                compiled: inputs.compiled,
                context: inputs.context,
                lockedMeals: locked,
                seed: seed,
                calendar: calendar
            )
        )
        let byID = Dictionary(catalogue.candidates.map { ($0.recipe.id, $0) }, uniquingKeysWith: { first, _ in first })
        var unmet: [Int] = []
        for (offset, rule) in adjustment.dayRules.sorted(by: { $0.key < $1.key }) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
            var compiled = inputs.compiled
            compiled.constraints += rule.diets.sorted { $0.rawValue < $1.rawValue }.map {
                DietaryConstraint(axis: .ethical, kind: .diet($0), strictness: .hard, source: .user, lastConfirmed: dates.now)
            }
            if let minutes = rule.maxCookMinutes { compiled.maxCookMinutes = minutes }
            let admission = { (candidate: RecipeCandidate) in compiled.admits(candidate, foods: catalogue.foods) }
            for meal in result.meals where calendar.isDate(meal.date, inSameDayAs: day) {
                if let candidate = byID[meal.recipeID], case .admitted = admission(candidate) { continue }
                guard !meal.isLocked,
                      let option = SwapSuggester.suggest(
                          for: meal, in: result, candidates: catalogue.candidates, admission: admission, context: inputs.context, limit: 1
                      ).first
                else {
                    unmet.append(offset)
                    continue
                }
                result.meals = Self.replacing(meal, with: option, in: result.meals)
            }
        }
        result.verification = PlanVerifier.verify(
            meals: result.meals,
            candidates: catalogue.candidates,
            foods: catalogue.foods,
            constraints: stored.constraints,
            targets: stored.targets,
            days: Self.weekDays,
            householdSize: stored.householdSize,
            slots: Set(slots)
        )
        return AdjustedWeek(result: result, unmetDayOffsets: Array(Set(unmet)).sorted())
    }

    /// `meals` with `meal` cooking `option` instead. A replaced leftover stands alone and hands its servings back to the
    /// meal it came from; leftovers of a replaced meal follow the new recipe, as they do for a swap.
    static func replacing(_ meal: PlannedMeal, with option: ScoredRecipe, in meals: [PlannedMeal]) -> [PlannedMeal] {
        meals.map { entry in
            var entry = entry
            if entry.id == meal.id {
                entry.recipeID = option.recipeID
                entry.reasonCodes = option.reasonCodes
                entry.leftoverOf = nil
            } else if entry.id == meal.leftoverOf {
                entry.servings = max(entry.servings - meal.servings, 1)
            } else if entry.leftoverOf == meal.id {
                entry.recipeID = option.recipeID
            }
            return entry
        }
    }
}
