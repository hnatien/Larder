import Foundation
import LarderCore

nonisolated extension PlanningService {
    /// Repairs `plan`'s `meals` as of now with `PlanRepairer`, against the stored profile, constraints, targets and pantry.
    ///
    /// `skipped` lists meals skipped since the meals were last planned or repaired; they already carry the status, and
    /// naming them lets the repair win back a nutrient band the skip lost. Pantry losses come from `pantryLosses`.
    public func repair(plan: MealPlan, meals: [PlannedMeal], skipped: Set<PlannedMealID> = [], slots: [MealType] = [.dinner]) async throws -> PlanRepair {
        let catalogue = try await catalogue()
        let inputs = try await inputs(catalogue: catalogue)
        let now = dates.now
        let losses = Self.pantryLosses(in: meals, pantry: inputs.context.pantry, today: calendar.startOfDay(for: now))
        let current = PlanResult(
            plan: plan,
            meals: meals,
            unfilledSlots: [],
            breakdown: PlanScoreBreakdown(mealScoreTotal: 0, nutrientPenalty: 0, varietyPenalty: 0, objective: 0),
            verification: VerificationReport(hardViolations: [], nutrientNotes: [], shelfBalance: ShelfBalance(levels: [:]))
        )
        return PlanRepairer.repair(
            current,
            today: now,
            events: PlanEvents(skipped: skipped, ranOut: losses.ranOut, expired: losses.expired),
            request: PlanRequest(
                startDate: plan.startDate,
                days: plan.days,
                slots: slots,
                candidates: catalogue.candidates,
                compiled: inputs.compiled,
                context: inputs.context,
                seed: plan.seed,
                planID: plan.id,
                calendar: calendar
            )
        )
    }

    /// Foods that planned meals from `today` on were chosen to use up (`usesExpiring`) and that the shelves no longer
    /// hold: `ranOut` when no item of the food is left, `expired` when every item left is past its best-by date.
    static func pantryLosses(in meals: [PlannedMeal], pantry: [PantryItem], today: Date) -> (ranOut: Set<FoodID>, expired: Set<FoodID>) {
        let counted = Set(meals.filter { $0.status == .planned && $0.date >= today }.flatMap { meal in
            meal.reasonCodes.compactMap { code -> FoodID? in if case .usesExpiring(let food, _) = code { food } else { nil } }
        })
        var ranOut = Set<FoodID>()
        var expired = Set<FoodID>()
        for food in counted {
            let left = pantry.filter { $0.foodID == food && $0.quantityGrams.isFinite && $0.quantityGrams > 0 }
            if left.isEmpty {
                ranOut.insert(food)
            } else if left.allSatisfy({ $0.bestBy.map { $0 < today } ?? false }) {
                expired.insert(food)
            }
        }
        return (ranOut, expired)
    }
}
