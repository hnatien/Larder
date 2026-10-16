import Foundation

/// Picks the free "Tonight" options: pantry-first, deterministic and offline.
public enum TonightPicker {
    /// Up to `limit` admitted dinner recipes, best first, each from a different cuisine.
    ///
    /// After the best recipe, each pick is the best remaining one whose cuisine is not yet shown and whose
    /// primary protein is new; when no such recipe is left, the protein preference is dropped but the cuisine
    /// rule is not, so fewer than `limit` come back when cuisines run out. Recipes without a cuisine never
    /// clash on cuisine. Uncertain and excluded candidates are never offered.
    public static func pick(
        candidates: [RecipeCandidate],
        admission: (RecipeCandidate) -> Admission,
        context: ScoringContext,
        limit: Int = 3
    ) -> [ScoredRecipe] {
        guard limit > 0 else { return [] }
        var remaining = RankedPool.rank(candidates.filter { $0.fits(.dinner) }, admission: admission, context: context)
        var picked: [ScoredRecipe] = []
        var cuisines = Set<String>()
        var proteins: [FoodTag?] = []

        while picked.count < limit {
            let open = remaining.indices.filter { index in
                remaining[index].candidate.recipe.tags.cuisine.map { !cuisines.contains($0.lowercased()) } ?? true
            }
            let fresh = open.first { !proteins.contains(primaryProtein(of: remaining[$0].candidate, foods: context.foods)) }
            guard let index = fresh ?? open.first else { break }
            let choice = remaining.remove(at: index)
            if let cuisine = choice.candidate.recipe.tags.cuisine { cuisines.insert(cuisine.lowercased()) }
            proteins.append(primaryProtein(of: choice.candidate, foods: context.foods))
            picked.append(choice)
        }
        return picked
    }

    /// Animal-protein tags, most specific first.
    private static let proteinTags: [FoodTag] = [.beef, .pork, .poultry, .fish, .shellfish, .egg, .meat]

    /// The protein tag of the heaviest tagged ingredient; `nil` for a recipe without animal protein.
    static func primaryProtein(of candidate: RecipeCandidate, foods: [FoodID: Food]) -> FoodTag? {
        var best: (tag: FoodTag, grams: Double)?
        for line in candidate.ingredients where !line.isGarnish {
            guard let food = line.foodID.flatMap({ foods[$0] }),
                  let tag = proteinTags.first(where: food.tags.contains)
            else { continue }
            let grams = IngredientGrams.resolve(line, food: food) ?? 0
            if best.map({ grams > $0.grams }) ?? true { best = (tag, grams) }
        }
        return best?.tag
    }
}
