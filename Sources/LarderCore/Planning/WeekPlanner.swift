import Foundation

/// Everything the week planner needs for one run.
public struct PlanRequest: Sendable {
    public var startDate: Date
    public var days: Int
    public var slots: [MealType]
    public var candidates: [RecipeCandidate]
    public var compiled: CompiledConstraints
    public var context: ScoringContext
    /// Meals the user pinned; kept exactly as given when their date falls inside the plan.
    public var lockedMeals: [PlannedMeal]
    public var seed: UInt64
    public var planID: MealPlanID
    /// Calendar used to step from one day to the next and to match locked meals to days.
    public var calendar: Calendar

    /// Creates a request.
    public init(
        startDate: Date,
        days: Int,
        slots: [MealType] = [.dinner],
        candidates: [RecipeCandidate],
        compiled: CompiledConstraints,
        context: ScoringContext,
        lockedMeals: [PlannedMeal] = [],
        seed: UInt64,
        planID: MealPlanID = MealPlanID(),
        calendar: Calendar = .current
    ) {
        self.startDate = startDate
        self.days = days
        self.slots = slots
        self.candidates = candidates
        self.compiled = compiled
        self.context = context
        self.lockedMeals = lockedMeals
        self.seed = seed
        self.planID = planID
        self.calendar = calendar
    }
}

/// How a plan's objective was made up.
public struct PlanScoreBreakdown: Hashable, Sendable {
    public var mealScoreTotal: Double
    public var nutrientPenalty: Double
    public var varietyPenalty: Double
    /// `mealScoreTotal - nutrientPenalty - varietyPenalty`.
    public var objective: Double

    /// Creates a breakdown.
    public init(mealScoreTotal: Double, nutrientPenalty: Double, varietyPenalty: Double, objective: Double) {
        self.mealScoreTotal = mealScoreTotal
        self.nutrientPenalty = nutrientPenalty
        self.varietyPenalty = varietyPenalty
        self.objective = objective
    }
}

/// A solved plan, its meals in day and meal-type order, the slots it could not fill and its verification.
public struct PlanResult: Sendable {
    public var plan: MealPlan
    public var meals: [PlannedMeal]
    public var unfilledSlots: [(date: Date, slot: MealType)]
    public var breakdown: PlanScoreBreakdown
    public var verification: VerificationReport

    /// Creates a result.
    public init(
        plan: MealPlan,
        meals: [PlannedMeal],
        unfilledSlots: [(date: Date, slot: MealType)],
        breakdown: PlanScoreBreakdown,
        verification: VerificationReport
    ) {
        self.plan = plan
        self.meals = meals
        self.unfilledSlots = unfilledSlots
        self.breakdown = breakdown
        self.verification = verification
    }
}

/// Builds a week of meals: seeded greedy fill, seeded local search, then independent verification and repair.
///
/// Only admitted candidates are planned; uncertain ones never are. A recipe appears once per plan except
/// as a leftover. The greedy fill takes, for each slot in day order, a seeded pick among the available
/// recipes scoring within `greedyBand` of the best, so a new seed gives a different week of similar quality.
/// Each cuisine appears at most ceil(days / 3) times per meal type; when nothing else fits the greedy fill
/// accepts a quota breach rather than leave a slot empty, the objective penalises it, and the local search
/// never adds one.
/// A recipe with at least twice the household's servings is cooked for two days when the next day's same
/// slot is free: the cooked meal gets twice the household servings and the next day a linked leftover of
/// one household's servings. Locked meals are never changed, even when the verifier flags them; unlocked
/// meals that fail verification are replaced, and dropped into `unfilledSlots` after three rounds.
/// Per-day nutrient targets are scaled to the share of the day the requested slots cover (`MealSlotShare`).
/// Each search move tries the best-scoring alternatives and, when the draft is outside a nutrient band, the
/// alternatives richest (or leanest, for a nutrient over its cap) in the nutrient that costs the objective most.
public enum WeekPlanner {
    /// Written to `MealPlan.solverVersion`.
    public static let solverVersion = "1.0"
    static let searchIterations = 200
    /// Score margin below the best within which the greedy fill picks at random.
    static let greedyBand = 0.25
    static let alternativesPerMove = 3
    /// Multiplies every nutrient's weighted squared deviation, so one swap toward a band can outweigh a small score
    /// difference: a week a fifth short of its fibre floor costs 0.24, a fifth under its energy floor 0.4.
    static let nutrientPenaltyScale = 10.0
    static let quotaPenalty = 2.0
    static let repairRounds = 3

    /// Plans `request`; never throws, an infeasible request comes back with unfilled slots.
    public static func plan(_ request: PlanRequest) -> PlanResult {
        plan(request) { request.compiled.admits($0, foods: request.context.foods) }
    }

    /// Plans with an explicit admission rule; the verifier still checks the result independently.
    static func plan(_ request: PlanRequest, admission: (RecipeCandidate) -> Admission) -> PlanResult {
        var solver = Solver(request: request, pool: RankedPool.rank(request.candidates, admission: admission, context: request.context))
        solver.fillGreedily()
        solver.search()
        let verification = solver.repair()
        return solver.result(verification: verification)
    }
}

/// Weight of each nutrient's squared band deviation in the plan objective, before `nutrientPenaltyScale`.
extension Nutrient {
    var penaltyWeight: Double {
        switch self {
        case .energy, .sodium: 1.0
        case .fiber, .protein: 0.6
        default: 0.4
        }
    }
}

private struct Slot: Hashable {
    var day: Int
    var type: MealType
}

/// How far a draft sits outside one nutrient's band, as a share of the bound it misses: negative under the floor,
/// positive over the cap.
struct NutrientGap {
    var nutrient: Nutrient
    var deviation: Double

    var penalty: Double { WeekPlanner.nutrientPenaltyScale * nutrient.penaltyWeight * deviation * deviation }

    /// Nutrients outside their band per person per day, one per target the data covers, in target order.
    static func gaps(
        in meals: [PlannedMeal],
        candidates: [RecipeID: RecipeCandidate],
        targets: [NutrientTarget],
        days: Int,
        householdSize: Int,
        coverage: Double
    ) -> [NutrientGap] {
        gaps(in: PlanNutrition(meals: meals, candidates: candidates), targets: targets, days: days, householdSize: householdSize, coverage: coverage)
    }

    /// Nutrients outside their band in `totals`, as `gaps(in:candidates:targets:days:householdSize:coverage:)`.
    static func gaps(in totals: PlanNutrition, targets: [NutrientTarget], days: Int, householdSize: Int, coverage: Double) -> [NutrientGap] {
        targets.compactMap { target in
            guard let value = totals.perPersonPerDay(target.nutrient, days: days, householdSize: householdSize),
                  let band = totals.dailyBand(for: target, days: days, householdSize: householdSize, coverage: coverage)
            else { return nil }
            if let low = band.min, low > 0, value < low {
                return NutrientGap(nutrient: target.nutrient, deviation: (value - low) / low)
            }
            if let high = band.max, high > 0, value > high {
                return NutrientGap(nutrient: target.nutrient, deviation: (value - high) / high)
            }
            return nil
        }
    }

    /// `options` that move the plan toward this band: most of the nutrient per serving first when under the
    /// floor, least first when over the cap; recipes without data for the nutrient are left out, and ties keep pool order.
    func closing(from options: [ScoredRecipe]) -> [ScoredRecipe] {
        options.enumerated()
            .compactMap { index, option in
                option.candidate.nutrition.perServing.value(of: nutrient).map { (option, index, $0) }
            }
            .sorted { lhs, rhs in
                if lhs.2 != rhs.2 { return deviation < 0 ? lhs.2 > rhs.2 : lhs.2 < rhs.2 }
                return lhs.1 < rhs.1
            }
            .map(\.0)
    }
}

private enum Entry {
    case locked(PlannedMeal)
    case cooked(RecipeID, id: PlannedMealID)
    case leftover(source: Slot, id: PlannedMealID)
}

private struct Solver {
    let request: PlanRequest
    let pool: [ScoredRecipe]
    let scores: [RecipeID: ScoredRecipe]
    let candidates: [RecipeID: RecipeCandidate]
    let dates: [Date]
    let household: Int
    let quota: Int
    /// Slots to fill, day by day in the request's slot order.
    let planned: [Slot]
    /// Share of the day the requested slots cover; scales per-day targets.
    let coverage: Double
    var entries: [Slot: Entry] = [:]
    var rejected = Set<RecipeID>()
    var random: SeededRandom

    init(request: PlanRequest, pool: [ScoredRecipe]) {
        self.request = request
        self.pool = pool
        random = SeededRandom(seed: request.seed)
        scores = Dictionary(pool.map { ($0.recipeID, $0) }, uniquingKeysWith: { first, _ in first })
        candidates = Dictionary(request.candidates.map { ($0.recipe.id, $0) }, uniquingKeysWith: { first, _ in first })
        let days = max(request.days, 0)
        dates = (0..<days).map { day in
            request.calendar.date(byAdding: .day, value: day, to: request.startDate)
                ?? request.startDate.addingTimeInterval(Double(day) * 86_400)
        }
        household = request.compiled.householdSize
        quota = (days + 2) / 3
        var types: [MealType] = []
        for type in request.slots where !types.contains(type) { types.append(type) }
        planned = (0..<days).flatMap { day in types.map { Slot(day: day, type: $0) } }
        coverage = MealSlotShare.coverage(slots: Set(types))

        for meal in request.lockedMeals {
            guard let day = dates.firstIndex(where: { request.calendar.isDate(meal.date, inSameDayAs: $0) }) else { continue }
            let slot = Slot(day: day, type: meal.slot)
            if entries[slot] == nil { entries[slot] = .locked(meal) }
        }
    }

    // MARK: Filling

    mutating func fillGreedily() {
        for slot in planned where entries[slot] == nil {
            let available = freshOptions(for: slot)
            guard let best = available.first else { continue }
            let band = available.prefix { $0.score >= best.score - WeekPlanner.greedyBand }
            let recipe = band[band.startIndex + Int(random.next(upperBound: UInt64(band.count)))]
            entries[slot] = .cooked(recipe.recipeID, id: PlannedMealID())
            let next = Slot(day: slot.day + 1, type: slot.type)
            if isBatch(recipe.recipeID), next.day < dates.count, entries[next] == nil {
                entries[next] = .leftover(source: slot, id: PlannedMealID())
            }
        }
    }

    mutating func search() {
        var current = breakdown().objective
        var worstGap = nutrientGaps(in: meals()).max { $0.penalty < $1.penalty }
        for _ in 0..<WeekPlanner.searchIterations {
            let movable = planned.filter { if case .cooked = entries[$0] { true } else { false } }
            guard !movable.isEmpty else { return }
            let slot = movable[Int(random.next(upperBound: UInt64(movable.count)))]
            guard case .cooked(let original, let id) = entries[slot] else { continue }
            let needsBatch = hasLeftover(slot)
            let open = pool.filter { alternative in
                alternative.recipeID != original && isAvailable(alternative, for: slot, replacing: original)
                    && !breachesQuota(alternative, at: slot, replacing: original)
                    && (!needsBatch || isBatch(alternative.recipeID))
            }
            var alternatives = Array(open.prefix(WeekPlanner.alternativesPerMove))
            if let worstGap {
                for alternative in worstGap.closing(from: open).prefix(WeekPlanner.alternativesPerMove)
                where !alternatives.contains(where: { $0.recipeID == alternative.recipeID }) {
                    alternatives.append(alternative)
                }
            }

            var best: (recipe: RecipeID, objective: Double)?
            for alternative in alternatives {
                entries[slot] = .cooked(alternative.recipeID, id: id)
                let objective = breakdown().objective
                if objective > (best?.objective ?? current) + 1e-9 { best = (alternative.recipeID, objective) }
            }
            if let best {
                entries[slot] = .cooked(best.recipe, id: id)
                current = best.objective
                worstGap = nutrientGaps(in: meals()).max { $0.penalty < $1.penalty }
            } else {
                entries[slot] = .cooked(original, id: id)
            }
        }
    }

    /// Re-verifies and replaces failing unlocked meals, then drops what still fails; returns the final report.
    mutating func repair() -> VerificationReport {
        for _ in 0..<WeekPlanner.repairRounds {
            let failing = failingSlots(in: verify())
            guard !failing.isEmpty else { break }
            var freed: [Slot] = []
            for slot in failing {
                if let recipe = recipe(at: slot) { rejected.insert(recipe) }
                freed += remove(slot)
            }
            for slot in planned where freed.contains(slot) && entries[slot] == nil {
                if let recipe = freshOptions(for: slot).first {
                    entries[slot] = .cooked(recipe.recipeID, id: PlannedMealID())
                }
            }
        }
        for slot in failingSlots(in: verify()) {
            _ = remove(slot)
        }
        return verify()
    }

    /// Admitted recipes for `slot` not yet planned or rejected, best first: those within the cuisine quota, or all when none is.
    private func freshOptions(for slot: Slot) -> [ScoredRecipe] {
        let available = pool.filter { isAvailable($0, for: slot, replacing: nil) }
        let withinQuota = available.filter { !breachesQuota($0, at: slot, replacing: nil) }
        return withinQuota.isEmpty ? available : withinQuota
    }

    private func isAvailable(_ recipe: ScoredRecipe, for slot: Slot, replacing current: RecipeID?) -> Bool {
        guard recipe.candidate.fits(slot.type), !rejected.contains(recipe.recipeID) else { return false }
        return recipe.recipeID == current || !plannedRecipes.contains(recipe.recipeID)
    }

    private func breachesQuota(_ recipe: ScoredRecipe, at slot: Slot, replacing current: RecipeID?) -> Bool {
        guard let cuisine = recipe.candidate.recipe.tags.cuisine?.lowercased() else { return false }
        let used = cookedRecipes(of: slot.type)
            .filter { $0 != current }
            .count { candidates[$0]?.recipe.tags.cuisine?.lowercased() == cuisine }
        return used >= quota
    }

    private func isBatch(_ recipe: RecipeID) -> Bool {
        (candidates[recipe]?.recipe.servings ?? 0) >= household * 2
    }

    private func hasLeftover(_ source: Slot) -> Bool {
        entries.values.contains { if case .leftover(source, _) = $0 { true } else { false } }
    }

    /// Clears `slot` and any leftovers of it; returns the cleared slots.
    private mutating func remove(_ slot: Slot) -> [Slot] {
        let children = entries.compactMap { key, entry -> Slot? in
            if case .leftover(slot, _) = entry { key } else { nil }
        }
        entries[slot] = nil
        for child in children { entries[child] = nil }
        return [slot] + children
    }

    // MARK: Reading the draft

    private func recipe(at slot: Slot) -> RecipeID? {
        switch entries[slot] {
        case .locked(let meal): meal.recipeID
        case .cooked(let recipe, _): recipe
        case .leftover(let source, _): recipe(at: source)
        case nil: nil
        }
    }

    private var plannedRecipes: Set<RecipeID> {
        Set(entries.keys.compactMap { recipe(at: $0) })
    }

    /// Recipes cooked (not leftovers) in slots of `type`.
    private func cookedRecipes(of type: MealType) -> [RecipeID] {
        entries.compactMap { slot, entry in
            guard slot.type == type else { return nil }
            switch entry {
            case .locked(let meal): return meal.leftoverOf == nil ? meal.recipeID : nil
            case .cooked(let recipe, _): return recipe
            case .leftover: return nil
            }
        }
    }

    private var orderedSlots: [Slot] {
        entries.keys.sorted { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day < rhs.day }
            return MealType.allCases.firstIndex(of: lhs.type) ?? 0 < MealType.allCases.firstIndex(of: rhs.type) ?? 0
        }
    }

    private func meals(withReasons: Bool = false) -> [PlannedMeal] {
        orderedSlots.compactMap { slot -> PlannedMeal? in
            switch entries[slot] {
            case .locked(let meal):
                return meal
            case .cooked(let recipe, let id):
                return PlannedMeal(
                    id: id, planID: request.planID, date: dates[slot.day], slot: slot.type, recipeID: recipe,
                    servings: hasLeftover(slot) ? household * 2 : household,
                    reasonCodes: withReasons ? scores[recipe]?.reasonCodes ?? [] : []
                )
            case .leftover(let source, let id):
                guard case .cooked(let recipe, let sourceID) = entries[source] else { return nil }
                return PlannedMeal(
                    id: id, planID: request.planID, date: dates[slot.day], slot: slot.type, recipeID: recipe,
                    servings: household, leftoverOf: sourceID, reasonCodes: [.leftoverOf(meal: sourceID)]
                )
            case nil:
                return nil
            }
        }
    }

    private func verify() -> VerificationReport {
        PlanVerifier.verify(
            meals: meals(),
            candidates: request.candidates,
            foods: request.context.foods,
            constraints: request.compiled.constraints,
            targets: request.compiled.targets,
            days: dates.count,
            householdSize: household,
            slots: Set(request.slots)
        )
    }

    /// Unlocked slots whose meal failed verification, in slot order.
    private func failingSlots(in report: VerificationReport) -> [Slot] {
        let failing = Set(report.hardViolations.map(\.plannedMealID))
        return orderedSlots.filter { slot in
            switch entries[slot] {
            case .cooked(_, let id), .leftover(_, let id): failing.contains(id)
            case .locked, nil: false
            }
        }
    }

    // MARK: Objective

    func breakdown() -> PlanScoreBreakdown {
        let meals = meals()
        let mealScore = meals.reduce(0) { total, meal in
            meal.leftoverOf == nil ? total + (scores[meal.recipeID]?.score ?? 0) : total
        }
        let nutrientPenalty = nutrientGaps(in: meals).reduce(0) { $0 + $1.penalty }
        let varietyPenalty = WeekPlanner.quotaPenalty * Double(quotaViolations)
        return PlanScoreBreakdown(
            mealScoreTotal: mealScore,
            nutrientPenalty: nutrientPenalty,
            varietyPenalty: varietyPenalty,
            objective: mealScore - nutrientPenalty - varietyPenalty
        )
    }

    /// Nutrients outside their band per person per day, one per target the data covers, in target order.
    private func nutrientGaps(in meals: [PlannedMeal]) -> [NutrientGap] {
        NutrientGap.gaps(
            in: meals, candidates: candidates, targets: request.compiled.targets, days: dates.count,
            householdSize: household, coverage: coverage
        )
    }

    /// Meals beyond the cuisine quota, counted per meal type.
    private var quotaViolations: Int {
        var counts: [String: Int] = [:]
        for type in MealType.allCases {
            for recipe in cookedRecipes(of: type) {
                guard let cuisine = candidates[recipe]?.recipe.tags.cuisine?.lowercased() else { continue }
                counts["\(type.rawValue)|\(cuisine)", default: 0] += 1
            }
        }
        return counts.values.reduce(0) { $0 + max($1 - quota, 0) }
    }

    // MARK: Result

    func result(verification: VerificationReport) -> PlanResult {
        var meals = meals(withReasons: true)
        if let fibre = verification.nutrientNotes.first(where: { $0.nutrient == .fiber && $0.status == .under }),
           let floor = fibre.min {
            let gramsShort = (floor - fibre.totalPerDay) * Double(dates.count)
            let richest = meals.indices
                .filter { meals[$0].leftoverOf == nil && !meals[$0].isLocked }
                .max { fibreGrams(meals[$0]) < fibreGrams(meals[$1]) }
            if let richest { meals[richest].reasonCodes.append(.fibreGap(gramsShort: gramsShort)) }
        }
        let unfilled = planned.filter { entries[$0] == nil }.map { (date: dates[$0.day], slot: $0.type) }
        let plan = MealPlan(
            id: request.planID,
            startDate: request.startDate,
            days: dates.count,
            constraintsSnapshot: request.compiled.snapshot,
            solverVersion: WeekPlanner.solverVersion,
            seed: request.seed,
            status: .draft
        )
        return PlanResult(plan: plan, meals: meals, unfilledSlots: unfilled, breakdown: breakdown(), verification: verification)
    }

    private func fibreGrams(_ meal: PlannedMeal) -> Double {
        (candidates[meal.recipeID]?.nutrition.perServing.fiberG ?? 0) * Double(meal.servings)
    }
}
