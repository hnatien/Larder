import Foundation

/// Ranks replacement recipes for one planned meal.
public enum SwapSuggester {
    /// Score added when a recipe shares at least `sharedFoodsForBonus` foods with the rest of the plan's shopping.
    static let sharedFoodsBonus = 0.5
    static let sharedFoodsForBonus = 2

    /// Up to `limit` admitted recipes that fit the meal's slot and are not already in the plan, best first.
    ///
    /// A recipe gains a bonus when it shares at least two foods with what the other meals still need from
    /// the shop (their ingredients not covered by the pantry), which keeps the grocery list short.
    public static func suggest(
        for meal: PlannedMeal,
        in result: PlanResult,
        candidates: [RecipeCandidate],
        admission: (RecipeCandidate) -> Admission,
        context: ScoringContext,
        limit: Int = 5
    ) -> [ScoredRecipe] {
        guard limit > 0 else { return [] }
        let inPlan = Set(result.meals.map(\.recipeID))
        let byID = Dictionary(candidates.map { ($0.recipe.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pantry = PantryIndex(context.pantry)
        let shopping = Set(
            result.meals
                .filter { $0.id != meal.id && $0.leftoverOf == nil && $0.recipeID != meal.recipeID }
                .flatMap { byID[$0.recipeID]?.ingredients ?? [] }
                .filter { !$0.isGarnish }
                .compactMap(\.foodID)
                .filter { pantry.grams[$0] == nil }
        )

        let ranked = RankedPool.rank(
            candidates.filter { $0.fits(meal.slot) && !inPlan.contains($0.recipe.id) },
            admission: admission,
            context: context
        )
        .map { scored -> ScoredRecipe in
            let foods = Set(scored.candidate.ingredients.filter { !$0.isGarnish }.compactMap(\.foodID))
            guard foods.intersection(shopping).count >= sharedFoodsForBonus else { return scored }
            var boosted = scored
            boosted.score += sharedFoodsBonus
            return boosted
        }
        .sorted(by: RankedPool.isRankedBefore)
        return Array(ranked.prefix(limit))
    }
}
