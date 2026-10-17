import Foundation

/// What the scorer knows about the user's kitchen and history.
public struct ScoringContext: Sendable {
    public var pantry: [PantryItem]
    public var foods: [FoodID: Food]
    public var now: Date
    /// When each recipe was last planned.
    public var recentlyPlanned: [RecipeID: Date]
    /// When each cuisine was last planned, keyed by cuisine name in any case.
    public var recentCuisines: [String: Date]
    /// What the household's history says it likes.
    public var taste: TasteAffinity
    public var goal: Goal
    public var maxCookMinutes: Int
    /// Carried for budget-aware callers; recipes have no prices yet, so scoring uses the pantry cost proxy.
    public var weeklyBudget: Decimal?
    /// Pantry foods the user asked to use up; a recipe using one scores as if it used something about to turn.
    public var useUp: Set<FoodID>

    /// Creates a scoring context.
    public init(
        pantry: [PantryItem],
        foods: [FoodID: Food],
        now: Date,
        recentlyPlanned: [RecipeID: Date] = [:],
        recentCuisines: [String: Date] = [:],
        taste: TasteAffinity = TasteAffinity(),
        goal: Goal,
        maxCookMinutes: Int,
        weeklyBudget: Decimal? = nil,
        useUp: Set<FoodID> = []
    ) {
        self.pantry = pantry
        self.foods = foods
        self.now = now
        self.recentlyPlanned = recentlyPlanned
        self.recentCuisines = recentCuisines
        self.taste = taste
        self.goal = goal
        self.maxCookMinutes = maxCookMinutes
        self.weeklyBudget = weeklyBudget
        self.useUp = useUp
    }
}

/// Unweighted score parts; each is 0...1 except `taste` and `nutrition`, which are -1...1.
public struct ScoreComponents: Hashable, Sendable {
    /// Fraction of non-optional, non-garnish ingredient grams the pantry covers.
    public var pantryOverlap: Double
    /// Sum over used pantry items expiring within 3 days of (3 - days left) / 3, each term and the sum capped at 1;
    /// 1 when the recipe uses a food the user asked to use up.
    public var expiryUrgency: Double
    /// 1 - total minutes / time cap, at least 0.
    public var timeFit: Double
    /// 1 - uncovered ingredient lines / ingredient lines; 0 for a recipe without lines.
    public var costProxy: Double
    /// 0 when planned within 14 days, rising linearly to 1 at 28 days; 1 when never planned.
    public var novelty: Double
    /// The recipe's `TasteAffinity`.
    public var taste: Double
    /// Protein grams per serving / 40, capped at 1; weighted only for the more-protein goal.
    public var protein: Double
    /// Half of fibre density and produce share, less sodium and saturated fat beyond their limits; weighted only for
    /// the eat-better goal (see `RecipeScorer.nutritionQuality`).
    public var nutrition: Double

    /// Creates components.
    public init(
        pantryOverlap: Double,
        expiryUrgency: Double,
        timeFit: Double,
        costProxy: Double,
        novelty: Double,
        taste: Double,
        protein: Double,
        nutrition: Double = 0
    ) {
        self.pantryOverlap = pantryOverlap
        self.expiryUrgency = expiryUrgency
        self.timeFit = timeFit
        self.costProxy = costProxy
        self.novelty = novelty
        self.taste = taste
        self.protein = protein
        self.nutrition = nutrition
    }
}

/// A candidate with its score, the parts it came from and the reasons to show.
public struct ScoredRecipe: Hashable, Sendable {
    public var candidate: RecipeCandidate
    public var score: Double
    public var components: ScoreComponents
    public var reasonCodes: [ReasonCode]

    /// Creates a scored recipe.
    public init(candidate: RecipeCandidate, score: Double, components: ScoreComponents, reasonCodes: [ReasonCode]) {
        self.candidate = candidate
        self.score = score
        self.components = components
        self.reasonCodes = reasonCodes
    }

    /// The recipe's identifier.
    public var recipeID: RecipeID { candidate.recipe.id }
}

/// Scores one candidate against the pantry, the clock and the user's history.
public enum RecipeScorer {
    /// Days within which a used pantry item counts as expiring.
    static let urgentDays = 3.0
    /// Total minutes at or under which a recipe is quick.
    static let quickMinutes = 25

    /// Weighted score with reason codes; weights follow `context.goal`.
    public static func score(_ candidate: RecipeCandidate, context: ScoringContext) -> ScoredRecipe {
        let pantry = PantryIndex(context.pantry)
        let lines = candidate.ingredients.filter { !$0.isGarnish }
        let required = lines.filter { !$0.isOptional }
        let usedFoods = Set(lines.compactMap(\.foodID)).filter { pantry.grams[$0] != nil }

        var remaining = pantry.grams
        var requiredGrams = 0.0
        var coveredGrams = 0.0
        for line in required {
            guard let grams = IngredientGrams.resolve(line, food: line.foodID.flatMap { context.foods[$0] }),
                  grams.isFinite, grams > 0
            else { continue }
            requiredGrams += grams
            if let foodID = line.foodID, let available = remaining[foodID] {
                let used = min(grams, available)
                coveredGrams += used
                remaining[foodID] = available - used
            }
        }

        let urgent = context.pantry
            .filter { item in item.foodID.map(usedFoods.contains) == true && item.quantityGrams > 0 }
            .compactMap { item -> (item: PantryItem, bestBy: Date, daysLeft: Double)? in
                guard let bestBy = item.bestBy else { return nil }
                let daysLeft = bestBy.timeIntervalSince(context.now) / 86_400
                return daysLeft <= urgentDays ? (item, bestBy, daysLeft) : nil
            }
            .sorted { ($0.bestBy, $0.item.id.rawValue.uuidString) < ($1.bestBy, $1.item.id.rawValue.uuidString) }

        let uncovered = required.filter { line in line.foodID.map { pantry.grams[$0] == nil } ?? true }.count
        let minutes = candidate.totalMinutes
        let components = ScoreComponents(
            pantryOverlap: requiredGrams > 0 ? coveredGrams / requiredGrams : 0,
            expiryUrgency: usedFoods.isDisjoint(with: context.useUp)
                ? min(urgent.reduce(0) { $0 + clamp((urgentDays - $1.daysLeft) / urgentDays) }, 1)
                : 1,
            timeFit: context.maxCookMinutes > 0 ? max(1 - Double(minutes) / Double(context.maxCookMinutes), 0) : 0,
            costProxy: required.isEmpty ? 0 : 1 - Double(uncovered) / Double(required.count),
            novelty: novelty(lastPlanned: context.recentlyPlanned[candidate.recipe.id], now: context.now),
            taste: context.taste.affinity(for: candidate.recipe.id),
            protein: clamp((candidate.nutrition.perServing.proteinG ?? 0) / 40),
            nutrition: nutritionQuality(candidate)
        )

        var codes: [ReasonCode] = urgent.compactMap { entry in
            entry.item.foodID.map { .usesExpiring(food: $0, bestBy: entry.bestBy) }
        }
        if usedFoods.count >= 2 { codes.append(.pantryOverlap(count: usedFoods.count)) }
        if minutes <= quickMinutes { codes.append(.quick(minutes: minutes)) }
        if let cuisine = candidate.recipe.tags.cuisine, !plannedRecently(cuisine, context: context) {
            codes.append(.varietyCuisine(cuisine: cuisine))
        }
        if context.goal == .saveMoney, components.costProxy >= 0.6 { codes.append(.underBudget) }
        if components.taste > 0, let reason = context.taste.reasons[candidate.recipe.id] { codes.append(reason) }

        return ScoredRecipe(
            candidate: candidate,
            score: Weights(goal: context.goal).apply(to: components),
            components: components,
            reasonCodes: codes
        )
    }

    /// Fibre per 1,000 kcal that earns full credit: the DGA 2025 density.
    static let fibrePer1000kcal = 14.0
    /// Sodium per 1,000 kcal at the DGA limit (2,300 mg in 2,000 kcal); double it is the full penalty.
    static let sodiumPer1000kcal = 1150.0
    /// Saturated fat share of energy at the DGA limit, in percent; double it is the full penalty.
    static let saturatedFatPercent = 10.0
    /// Share of the recipe's grams from produce and pulses that earns full credit.
    static let plantShare = 0.5

    /// How well a serving fits healthy-eating guidance, -1...1: half of (fibre density against 14 g per 1,000 kcal
    /// plus produce-and-pulse share against half the plate, each capped at 1) minus half of (sodium density and
    /// saturated-fat energy share beyond their limits, each reaching 1 at twice the limit). Densities need the
    /// serving's energy; a nutrient without data adds nothing either way.
    static func nutritionQuality(_ candidate: RecipeCandidate) -> Double {
        let serving = candidate.nutrition.perServing
        let totalGrams = candidate.foodGroupsGrams.values.reduce(0, +)
        let plants = (candidate.foodGroupsGrams[.produce] ?? 0) + (candidate.foodGroupsGrams[.legumes] ?? 0)
        var gains = totalGrams > 0 ? clamp(plants / totalGrams / plantShare) : 0
        var losses = 0.0
        if let kcal = serving.energyKcal, kcal.isFinite, kcal > 0 {
            if let fibre = serving.fiberG { gains += clamp(fibre / kcal * 1000 / fibrePer1000kcal) }
            if let sodium = serving.sodiumMg { losses += clamp((sodium / kcal * 1000 - sodiumPer1000kcal) / sodiumPer1000kcal) }
            if let saturated = serving.saturatedFatG {
                losses += clamp((saturated * 9 / kcal * 100 - saturatedFatPercent) / saturatedFatPercent)
            }
        }
        return (gains - losses) / 2
    }

    private static func novelty(lastPlanned: Date?, now: Date) -> Double {
        guard let lastPlanned else { return 1 }
        let days = now.timeIntervalSince(lastPlanned) / 86_400
        return clamp((days - 14) / 14)
    }

    private static func plannedRecently(_ cuisine: String, context: ScoringContext) -> Bool {
        let key = cuisine.lowercased()
        return context.recentCuisines.contains { name, date in
            name.lowercased() == key && context.now.timeIntervalSince(date) < 7 * 86_400
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private struct Weights {
        var pantryOverlap = 1.0
        var expiryUrgency = 1.0
        var timeFit = 1.0
        var costProxy = 1.0
        var novelty = 1.0
        var taste = 1.0
        var protein = 0.0
        var nutrition = 0.0

        init(goal: Goal) {
            switch goal {
            case .lessWaste:
                pantryOverlap = 2
                expiryUrgency = 2
            case .saveMoney: costProxy = 2
            case .moreVariety: novelty = 2
            case .moreProtein: protein = 1
            case .eatBetter: nutrition = 2
            case .maintain: break
            }
        }

        func apply(to c: ScoreComponents) -> Double {
            pantryOverlap * c.pantryOverlap + expiryUrgency * c.expiryUrgency + timeFit * c.timeFit
                + costProxy * c.costProxy + novelty * c.novelty + taste * c.taste + protein * c.protein
                + nutrition * c.nutrition
        }
    }
}

/// Pantry grams per food, counting only items with a food and a positive amount.
struct PantryIndex {
    var grams: [FoodID: Double]

    init(_ items: [PantryItem]) {
        grams = items.reduce(into: [:]) { totals, item in
            guard let foodID = item.foodID, item.quantityGrams.isFinite, item.quantityGrams > 0 else { return }
            totals[foodID, default: 0] += item.quantityGrams
        }
    }
}

/// Admitted candidates scored and ranked, shared by Tonight, the week planner and swaps.
enum RankedPool {
    /// Score taken off per soft-constraint penalty, so soft rules lower a recipe without hiding it.
    static let softPenaltyWeight = 0.5

    /// Admitted candidates, one per recipe, best first; ties break by title, then identifier.
    static func rank(
        _ candidates: [RecipeCandidate],
        admission: (RecipeCandidate) -> Admission,
        context: ScoringContext
    ) -> [ScoredRecipe] {
        var seen = Set<RecipeID>()
        var ranked: [ScoredRecipe] = []
        for candidate in candidates where seen.insert(candidate.recipe.id).inserted {
            guard case .admitted(let penalties) = admission(candidate) else { continue }
            var scored = RecipeScorer.score(candidate, context: context)
            scored.score -= softPenaltyWeight * Double(penalties.count)
            ranked.append(scored)
        }
        return ranked.sorted(by: isRankedBefore)
    }

    static func isRankedBefore(_ lhs: ScoredRecipe, _ rhs: ScoredRecipe) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.candidate.recipe.title != rhs.candidate.recipe.title {
            return lhs.candidate.recipe.title < rhs.candidate.recipe.title
        }
        return lhs.recipeID.rawValue.uuidString < rhs.recipeID.rawValue.uuidString
    }
}
