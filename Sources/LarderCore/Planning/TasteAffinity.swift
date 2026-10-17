import Foundation

/// How much the household seems to like each recipe, from -1 (avoid) through 0 (no signal) to 1, learned on device.
///
/// `learn` reads the meal history: a cooked meal adds 1, a skipped one takes off 0.5 and each time a recipe was
/// swapped out of a slot takes off 0.4, every event halving in weight each `halfLifeDays`. Leftovers add nothing,
/// because their cooked meal already counted. A recipe's affinity is tanh of its own evidence plus `spread` times
/// the evidence of other recipes in its cuisine and, averaged over its main ingredients, of other recipes sharing
/// each one, so cooking a lot of Indian food warms the Indian recipes not yet tried. Everything is a pure function
/// of the history, the candidates and `now`, whatever order the history arrives in.
public struct TasteAffinity: Hashable, Sendable {
    /// Affinity per recipe, -1...1; a recipe without an entry has no signal.
    public var values: [RecipeID: Double]
    /// Why a recipe with positive affinity fits: a cuisine or an ingredient the household cooks often.
    public var reasons: [RecipeID: ReasonCode]

    /// Creates an affinity from known values.
    public init(values: [RecipeID: Double] = [:], reasons: [RecipeID: ReasonCode] = [:]) {
        self.values = values
        self.reasons = reasons
    }

    /// The recipe's affinity; 0 without a signal.
    public func affinity(for recipe: RecipeID) -> Double {
        values[recipe] ?? 0
    }

    static let halfLifeDays = 21.0
    static let cookedWeight = 1.0
    static let skippedWeight = -0.5
    static let swappedAwayWeight = -0.4
    /// Share of neighbouring recipes' evidence a recipe takes on.
    static let spread = 0.25
    /// Decayed cooked meals of a cuisine or main ingredient from which it reads as cooked often.
    static let cookedOften = 2.0
    /// Main ingredients per recipe.
    static let mainIngredientCount = 2
    /// Groups that are staples or seasoning rather than what a dish is about.
    private static let backgroundGroups: Set<FoodGroup> = [.grains, .fats, .other]

    /// Affinity for every candidate from `history`; meals of recipes missing from `candidates` still count toward
    /// their own recipe but cannot spread.
    public static func learn(
        from history: [PlannedMeal],
        candidates: [RecipeCandidate],
        foods: [FoodID: Food],
        now: Date
    ) -> TasteAffinity {
        var evidence: [RecipeID: Double] = [:]
        var cooked: [RecipeID: Double] = [:]
        // Date then identifier order, so the sums do not depend on the order `history` arrives in.
        let ordered = history.sorted { ($0.date, $0.id.rawValue.uuidString) < ($1.date, $1.id.rawValue.uuidString) }
        for meal in ordered where meal.leftoverOf == nil {
            let decay = pow(0.5, max(now.timeIntervalSince(meal.date), 0) / 86_400 / halfLifeDays)
            switch meal.status {
            case .cooked:
                evidence[meal.recipeID, default: 0] += cookedWeight * decay
                cooked[meal.recipeID, default: 0] += decay
            case .skipped:
                evidence[meal.recipeID, default: 0] += skippedWeight * decay
            case .planned:
                break
            }
            for swapped in meal.swapHistory {
                evidence[swapped, default: 0] += swappedAwayWeight * decay
            }
        }

        var cuisine: [RecipeID: String] = [:]
        var mains: [RecipeID: [FoodID]] = [:]
        for candidate in candidates where cuisine[candidate.recipe.id] == nil && mains[candidate.recipe.id] == nil {
            cuisine[candidate.recipe.id] = candidate.recipe.tags.cuisine?.lowercased()
            mains[candidate.recipe.id] = mainIngredients(of: candidate, foods: foods)
        }

        // Summed in identifier order so the result does not depend on dictionary order.
        var cuisineEvidence: [String: Double] = [:]
        var cuisineCooked: [String: Double] = [:]
        var foodEvidence: [FoodID: Double] = [:]
        var foodCooked: [FoodID: Double] = [:]
        for recipe in evidence.keys.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            let own = evidence[recipe] ?? 0
            let times = cooked[recipe] ?? 0
            if let name = cuisine[recipe] {
                cuisineEvidence[name, default: 0] += own
                cuisineCooked[name, default: 0] += times
            }
            for food in mains[recipe] ?? [] {
                foodEvidence[food, default: 0] += own
                foodCooked[food, default: 0] += times
            }
        }

        var affinity = TasteAffinity()
        for candidate in candidates {
            let id = candidate.recipe.id
            guard affinity.values[id] == nil else { continue }
            let own = evidence[id] ?? 0
            let name = cuisine[id]
            let foods = mains[id] ?? []
            let fromCuisine = name.map { (cuisineEvidence[$0] ?? 0) - own } ?? 0
            let fromFoods = foods.isEmpty ? 0 : foods.reduce(0) { $0 + (foodEvidence[$1] ?? 0) - own } / Double(foods.count)
            let value = tanh(own + spread * (fromCuisine + fromFoods))
            guard value != 0 else { continue }
            affinity.values[id] = value
            guard value > 0 else { continue }
            if let name, (cuisineCooked[name] ?? 0) >= cookedOften, let display = candidate.recipe.tags.cuisine {
                affinity.reasons[id] = .cooksOften(cuisine: display)
            } else if let food = foods.filter({ (foodCooked[$0] ?? 0) >= cookedOften }).max(by: { (foodCooked[$0] ?? 0) < (foodCooked[$1] ?? 0) }) {
                affinity.reasons[id] = .cooksOftenWith(food: food)
            }
        }
        return affinity
    }

    /// The heaviest non-garnish foods outside staples and seasoning, heaviest first; ties keep line order.
    static func mainIngredients(of candidate: RecipeCandidate, foods: [FoodID: Food]) -> [FoodID] {
        var grams: [(food: FoodID, grams: Double)] = []
        for line in candidate.ingredients where !line.isGarnish {
            guard let foodID = line.foodID, let food = foods[foodID], !backgroundGroups.contains(food.foodGroup),
                  let amount = IngredientGrams.resolve(line, food: food), amount.isFinite, amount > 0
            else { continue }
            if let index = grams.firstIndex(where: { $0.food == foodID }) {
                grams[index].grams += amount
            } else {
                grams.append((foodID, amount))
            }
        }
        return grams.enumerated()
            .sorted { lhs, rhs in lhs.element.grams != rhs.element.grams ? lhs.element.grams > rhs.element.grams : lhs.offset < rhs.offset }
            .prefix(mainIngredientCount)
            .map(\.element.food)
    }
}
