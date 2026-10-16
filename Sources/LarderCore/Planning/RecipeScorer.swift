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
    public var liked: Set<RecipeID>
    public var skipped: Set<RecipeID>
    public var goal: Goal
    public var maxCookMinutes: Int
    /// Carried for budget-aware callers; recipes have no prices yet, so scoring uses the pantry cost proxy.
    public var weeklyBudget: Decimal?

    /// Creates a scoring context.
    public init(
        pantry: [PantryItem],
        foods: [FoodID: Food],
        now: Date,
        recentlyPlanned: [RecipeID: Date] = [:],
        recentCuisines: [String: Date] = [:],
        liked: Set<RecipeID> = [],
        skipped: Set<RecipeID> = [],
        goal: Goal,
        maxCookMinutes: Int,
        weeklyBudget: Decimal? = nil
    ) {
        self.pantry = pantry
        self.foods = foods
        self.now = now
        self.recentlyPlanned = recentlyPlanned
        self.recentCuisines = recentCuisines
        self.liked = liked
        self.skipped = skipped
        self.goal = goal
        self.maxCookMinutes = maxCookMinutes
        self.weeklyBudget = weeklyBudget
    }
}

/// Unweighted score parts; each is 0...1 except `taste`, which is -1...1.
public struct ScoreComponents: Hashable, Sendable {
    /// Fraction of non-optional, non-garnish ingredient grams the pantry covers.
    public var pantryOverlap: Double
    /// Sum over used pantry items expiring within 3 days of (3 - days left) / 3, each term and the sum capped at 1.
    public var expiryUrgency: Double
    /// 1 - total minutes / time cap, at least 0.
    public var timeFit: Double
    /// 1 - uncovered ingredient lines / ingredient lines; 0 for a recipe without lines.
    public var costProxy: Double
    /// 0 when planned within 14 days, rising linearly to 1 at 28 days; 1 when never planned.
    public var novelty: Double
    /// 1 liked, -1 skipped, 0 otherwise.
    public var taste: Double
    /// Protein grams per serving / 40, capped at 1; weighted only for the more-protein goal.
    public var protein: Double

    /// Creates components.
    public init(
        pantryOverlap: Double,
        expiryUrgency: Double,
        timeFit: Double,
        costProxy: Double,
        novelty: Double,
        taste: Double,
        protein: Double
    ) {
        self.pantryOverlap = pantryOverlap
        self.expiryUrgency = expiryUrgency
        self.timeFit = timeFit
        self.costProxy = costProxy
        self.novelty = novelty
        self.taste = taste
        self.protein = protein
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
            expiryUrgency: min(urgent.reduce(0) { $0 + clamp((urgentDays - $1.daysLeft) / urgentDays) }, 1),
            timeFit: context.maxCookMinutes > 0 ? max(1 - Double(minutes) / Double(context.maxCookMinutes), 0) : 0,
            costProxy: required.isEmpty ? 0 : 1 - Double(uncovered) / Double(required.count),
            novelty: novelty(lastPlanned: context.recentlyPlanned[candidate.recipe.id], now: context.now),
            taste: (context.liked.contains(candidate.recipe.id) ? 1 : 0) - (context.skipped.contains(candidate.recipe.id) ? 1 : 0),
            protein: clamp((candidate.nutrition.perServing.proteinG ?? 0) / 40)
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

        return ScoredRecipe(
            candidate: candidate,
            score: Weights(goal: context.goal).apply(to: components),
            components: components,
            reasonCodes: codes
        )
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

        init(goal: Goal) {
            switch goal {
            case .lessWaste:
                pantryOverlap = 2
                expiryUrgency = 2
            case .saveMoney: costProxy = 2
            case .moreVariety: novelty = 2
            case .moreProtein: protein = 1
            case .eatBetter, .maintain: break
            }
        }

        func apply(to c: ScoreComponents) -> Double {
            pantryOverlap * c.pantryOverlap + expiryUrgency * c.expiryUrgency + timeFit * c.timeFit
                + costProxy * c.costProxy + novelty * c.novelty + taste * c.taste + protein * c.protein
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
