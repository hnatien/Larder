import Foundation

/// What happened to a plan since it was made.
public struct PlanEvents: Hashable, Sendable {
    /// Meals the user skipped.
    public var skipped: Set<PlannedMealID>
    /// Meals the user cooked.
    public var cooked: Set<PlannedMealID>
    /// Foods the plan counted on that are no longer on the shelves.
    public var ranOut: Set<FoodID>
    /// Foods the plan counted on that passed their best-by date.
    public var expired: Set<FoodID>

    /// Creates events.
    public init(
        skipped: Set<PlannedMealID> = [],
        cooked: Set<PlannedMealID> = [],
        ranOut: Set<FoodID> = [],
        expired: Set<FoodID> = []
    ) {
        self.skipped = skipped
        self.cooked = cooked
        self.ranOut = ranOut
        self.expired = expired
    }
}

/// One meal a repair changed.
public struct PlanChange: Hashable, Sendable {
    /// What happened to the meal.
    public enum Action: Hashable, Sendable {
        /// The meal now sits on `date`, moved from this day.
        case moved(from: Date)
        /// The slot now cooks `recipeID` in place of this recipe.
        case replaced(previous: RecipeID)
        /// The meal left the plan.
        case removed
    }

    public var mealID: PlannedMealID
    /// The meal's day after the change; for a removed meal, the day it was on.
    public var date: Date
    public var slot: MealType
    /// The recipe the slot cooks after the change; for a removed meal, the recipe that left.
    public var recipeID: RecipeID
    public var action: Action
    public var cause: RepairCause

    /// Creates a change.
    public init(mealID: PlannedMealID, date: Date, slot: MealType, recipeID: RecipeID, action: Action, cause: RepairCause) {
        self.mealID = mealID
        self.date = date
        self.slot = slot
        self.recipeID = recipeID
        self.action = action
        self.cause = cause
    }
}

/// A repaired plan and the meals that changed to get there.
public struct PlanRepair: Sendable {
    public var result: PlanResult
    /// One entry per changed meal, in day and meal-type order; empty when the week needed nothing.
    public var changes: [PlanChange]

    /// Creates a repair.
    public init(result: PlanResult, changes: [PlanChange]) {
        self.result = result
        self.changes = changes
    }
}

/// Repairs a plan after the week deviated from it, changing as few meals as it can.
///
/// Past days, cooked, skipped and locked meals are fixed; only planned, unlocked meals from today on change.
/// In order:
/// 1. An uncooked meal from a past day moves to the first day from today whose same slot is empty, when the
///    pantry (items not past their best-by date) still holds every ingredient line that names a food and the move
///    leaves no nutrient band missed that was met before it; otherwise it is dropped. Its leftovers keep their
///    distance from it when that day is free, and are dropped otherwise, handing their servings back.
/// 2. A leftover whose cooked meal was skipped or dropped is removed.
/// 3. A meal that needs a food in `ranOut` or `expired` that the pantry no longer holds is replaced.
/// 4. Slots a removed leftover left empty are filled again; replacements and refills take a seeded pick among the
///    admitted recipes not in the plan, not needing a lost food and within the cuisine quota, as the week planner
///    does, and carry `replacedBecause` with the cause. A meal with a leftover is only replaced by a batch recipe.
/// 5. After any deviation, a seeded local search like `WeekPlanner`'s swaps editable meals against the plan
///    objective less `changePenalty` per changed meal (a leftover following its cooked meal counts with it) and `bandPenalty` per nutrient band the original week met and
///    the repaired one misses. It takes only swaps that also improve the week's nutrition (or undo an earlier
///    swap), so a slot changes for a nutrient band, never for a slightly better recipe.
/// 6. The verifier re-checks the week; a changed meal that fails is dropped.
public enum PlanRepairer {
    /// Objective taken off per changed meal: more than most score gains between recipes, so a meal changes for a
    /// nutrient band or a deviation, not for a slightly better recipe.
    static let changePenalty = 2.5
    /// Objective taken off per nutrient band the original week met and the repaired week misses; above
    /// `changePenalty`, so one swap that wins a band back pays for itself.
    static let bandPenalty = 5.0

    /// Repairs `current` as of `today` after `events`.
    ///
    /// `request` supplies the candidates, constraints, scoring context (with the current pantry), slots, seed and
    /// calendar; its start date, days and locked meals are ignored in favour of the plan's own. Never throws: a
    /// slot from today on that nothing fills comes back in `unfilledSlots`.
    public static func repair(_ current: PlanResult, today: Date, events: PlanEvents, request: PlanRequest) -> PlanRepair {
        repair(current, today: today, events: events, request: request) { request.compiled.admits($0, foods: request.context.foods) }
    }

    /// Repairs with an explicit admission rule; the verifier still checks the result independently.
    static func repair(
        _ current: PlanResult,
        today: Date,
        events: PlanEvents,
        request: PlanRequest,
        admission: (RecipeCandidate) -> Admission
    ) -> PlanRepair {
        var repairer = Repairer(
            current: current,
            today: today,
            events: events,
            request: request,
            pool: RankedPool.rank(request.candidates, admission: admission, context: request.context)
        )
        repairer.carryForwardPastMeals()
        repairer.removeOrphanedLeftovers()
        repairer.replacePantryLosses()
        repairer.refillVacancies()
        repairer.search()
        let verification = repairer.backstop()
        return repairer.repair(verification: verification)
    }
}

private struct Repairer {
    let request: PlanRequest
    let plan: MealPlan
    let events: PlanEvents
    let pool: [ScoredRecipe]
    let scores: [RecipeID: ScoredRecipe]
    let candidates: [RecipeID: RecipeCandidate]
    let dates: [Date]
    /// Plan day of each date in `dates`, so most lookups skip the calendar.
    let dayByDate: [Date: Int]
    /// Day index of today in the plan; may fall before or after it.
    let todayIndex: Int
    let household: Int
    let quota: Int
    let coverage: Double
    /// Non-expired pantry grams per food.
    let available: [FoodID: Double]
    /// The meals as the plan made them, with this period's skips undone, keyed by identifier.
    let original: [PlannedMealID: PlannedMeal]
    /// Nutrients whose band the original week met; set once at the end of `init`.
    private(set) var baselineBands = Set<Nutrient>()
    var meals: [PlannedMeal]
    /// Why each changed or removed meal changed.
    var causes: [PlannedMealID: RepairCause] = [:]
    /// Slots emptied by a removed leftover, to fill again, keyed by the removed meal.
    var vacancies: [PlannedMeal] = []
    /// Recipes a deviation took out of the week; never put back.
    var retired = Set<RecipeID>()
    var random: SeededRandom

    init(current: PlanResult, today: Date, events: PlanEvents, request: PlanRequest, pool: [ScoredRecipe]) {
        self.request = request
        self.events = events
        self.pool = pool
        plan = current.plan
        random = SeededRandom(seed: request.seed)
        scores = Dictionary(pool.map { ($0.recipeID, $0) }, uniquingKeysWith: { first, _ in first })
        candidates = Dictionary(request.candidates.map { ($0.recipe.id, $0) }, uniquingKeysWith: { first, _ in first })
        let calendar = request.calendar
        let days = max(current.plan.days, 0)
        dates = (0..<days).map { day in
            calendar.date(byAdding: .day, value: day, to: current.plan.startDate)
                ?? current.plan.startDate.addingTimeInterval(Double(day) * 86_400)
        }
        dayByDate = Dictionary(dates.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let start = calendar.startOfDay(for: current.plan.startDate)
        let todayStart = calendar.startOfDay(for: today)
        todayIndex = calendar.dateComponents([.day], from: start, to: todayStart).day ?? 0
        household = request.compiled.householdSize
        quota = (days + 2) / 3
        var types: [MealType] = []
        for type in request.slots where !types.contains(type) { types.append(type) }
        coverage = MealSlotShare.coverage(slots: Set(types))
        available = request.context.pantry.reduce(into: [:]) { totals, item in
            guard let foodID = item.foodID, item.quantityGrams.isFinite, item.quantityGrams > 0,
                  item.bestBy.map({ $0 >= todayStart }) ?? true
            else { return }
            totals[foodID, default: 0] += item.quantityGrams
        }

        let baseline = current.meals.map { meal in
            var meal = meal
            if events.skipped.contains(meal.id), meal.status == .skipped { meal.status = .planned }
            return meal
        }
        original = Dictionary(baseline.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        meals = current.meals.map { meal in
            var meal = meal
            if events.cooked.contains(meal.id) {
                meal.status = .cooked
            } else if events.skipped.contains(meal.id) {
                meal.status = .skipped
            }
            return meal
        }
        baselineBands = metBands(in: baseline)
    }

    // MARK: Deviations

    /// Moves each uncooked meal from a past day to the first free same-slot day the pantry still covers, or drops it.
    mutating func carryForwardPastMeals() {
        let past = ordered(meals.filter { meal in
            meal.leftoverOf == nil && meal.status == .planned && !meal.isLocked
                && day(of: meal.date).map { (0..<todayIndex).contains($0) } == true
        })
        for meal in past {
            guard let current = meals.first(where: { $0.id == meal.id }) else { continue }
            if let moved = move(current) {
                meals = moved
                causes[current.id] = .notCooked
                for leftover in leftovers(of: current.id, in: original.values) { causes[leftover.id] = .notCooked }
            } else {
                remove(current, cause: .notCooked)
            }
        }
    }

    /// The meals with `meal` on the first free day from today, its leftovers following or dropped, when the pantry
    /// covers it and no band met before the move is missed after it; `nil` otherwise.
    private func move(_ meal: PlannedMeal) -> [PlannedMeal]? {
        let children = Set(leftovers(of: meal.id, in: meals).filter { $0.status == .planned && !$0.isLocked }.map(\.id))
        guard let from = day(of: meal.date),
              let target = (max(todayIndex, 0)..<dates.count).first(where: { isFree($0, meal.slot, ignoring: children) })
        else { return nil }
        var trial = meals
        guard let index = trial.firstIndex(where: { $0.id == meal.id }) else { return nil }
        trial[index].date = dates[target]
        trial[index].reasonCodes = [.movedFrom(date: meal.date)] + meal.reasonCodes.filter {
            if case .movedFrom = $0 { false } else { true }
        }
        for child in ordered(trial.filter { children.contains($0.id) }) {
            let offset = (day(of: child.date) ?? from) - from
            let next = target + max(offset, 1)
            let childIndex = trial.firstIndex { $0.id == child.id }
            if next < dates.count, isFree(next, child.slot, ignoring: [child.id], in: trial), let childIndex {
                trial[childIndex].date = dates[next]
            } else {
                trial.removeAll { $0.id == child.id }
                if let source = trial.firstIndex(where: { $0.id == meal.id }) {
                    trial[source].servings = max(trial[source].servings - child.servings, 1)
                }
            }
        }
        guard let moved = trial.first(where: { $0.id == meal.id }), covers(moved),
              metBands(in: meals).subtracting(metBands(in: trial)).isEmpty
        else { return nil }
        return trial
    }

    /// Removes leftovers from today on whose cooked meal was skipped.
    mutating func removeOrphanedLeftovers() {
        let skipped = Set(meals.filter { $0.status == .skipped }.map(\.id))
        for leftover in ordered(meals.filter { $0.leftoverOf.map(skipped.contains) == true && isEditable($0) }) {
            remove(leftover, cause: .skipped)
        }
    }

    /// Replaces meals from today on that need a food the plan lost and the pantry no longer holds.
    mutating func replacePantryLosses() {
        for meal in ordered(meals.filter { $0.leftoverOf == nil && isEditable($0) }) {
            guard let current = meals.first(where: { $0.id == meal.id }),
                  let candidate = candidates[current.recipeID], let food = lostFood(in: candidate)
            else { continue }
            let cause: RepairCause = events.expired.contains(food) ? .expired(food: food) : .outOfStock(food: food)
            retired.insert(current.recipeID)
            replace(current, cause: cause)
        }
    }

    /// Fills the slots removed leftovers left, earliest first.
    mutating func refillVacancies() {
        for vacancy in ordered(vacancies) where isFree(day(of: vacancy.date) ?? -1, vacancy.slot, ignoring: []) {
            guard let option = pick(from: freshOptions(for: vacancy, batch: false)) else { continue }
            var meal = vacancy
            meal.recipeID = option.recipeID
            meal.servings = household
            meal.leftoverOf = nil
            meal.isLocked = false
            meal.status = .planned
            meal.reasonCodes = [.replacedBecause(cause: causes[vacancy.id] ?? .balance)] + option.reasonCodes
            meals.append(meal)
        }
        vacancies = []
    }

    /// Puts a fresh recipe in `meal`'s slot; leftovers follow a batch recipe, else they go and their slots refill.
    /// Without any option the meal is removed.
    private mutating func replace(_ meal: PlannedMeal, cause: RepairCause) {
        let children = leftovers(of: meal.id, in: meals).filter(isEditable)
        let option = children.isEmpty ? nil : pick(from: freshOptions(for: meal, batch: true))
        guard let option = option ?? pick(from: freshOptions(for: meal, batch: false)) else {
            remove(meal, cause: cause)
            return
        }
        let keepsLeftovers = !children.isEmpty && isBatch(option.recipeID)
        if !keepsLeftovers {
            for child in children { remove(child, cause: cause) }
        }
        causes[meal.id] = cause
        meals = meals.map { entry in
            var entry = entry
            if entry.id == meal.id {
                entry.recipeID = option.recipeID
                entry.servings = keepsLeftovers ? household * 2 : household
                entry.reasonCodes = [.replacedBecause(cause: cause)] + option.reasonCodes
            } else if keepsLeftovers, entry.leftoverOf == meal.id {
                entry.recipeID = option.recipeID
                causes[entry.id] = cause
            }
            return entry
        }
    }

    /// Takes `meal` and its leftovers out; editable leftovers from today on leave a vacancy to refill.
    private mutating func remove(_ meal: PlannedMeal, cause: RepairCause) {
        causes[meal.id] = cause
        retired.insert(meal.recipeID)
        meals.removeAll { $0.id == meal.id }
        if meal.leftoverOf != nil, isEditable(meal) { vacancies.append(meal) }
        if meal.leftoverOf != nil, let source = meal.leftoverOf, let index = meals.firstIndex(where: { $0.id == source }),
           meals[index].status != .skipped, isEditable(meals[index]) {
            meals[index].servings = max(meals[index].servings - meal.servings, 1)
        }
        for child in leftovers(of: meal.id, in: meals) where child.status == .planned && !child.isLocked {
            remove(child, cause: cause)
        }
    }

    // MARK: Search

    /// Seeded local search over editable meals against the objective with its change and band penalties.
    ///
    /// Runs only after a deviation, and takes a swap only when it also lowers the nutrient and band penalties or
    /// undoes an earlier swap, so a week that went to plan never changes and `.balance` always means nutrition.
    mutating func search() {
        guard !causes.isEmpty || !events.skipped.isEmpty else { return }
        var current = evaluate(meals)
        for _ in 0..<WeekPlanner.searchIterations {
            let movable = meals.filter { $0.leftoverOf == nil && isEditable($0) }
            guard !movable.isEmpty else { return }
            let meal = ordered(movable)[Int(random.next(upperBound: UInt64(movable.count)))]
            let needsBatch = !leftovers(of: meal.id, in: meals).filter(isEditable).isEmpty
            let open = openOptions(for: meal, batch: needsBatch)
            var alternatives = Array(open.prefix(WeekPlanner.alternativesPerMove))
            if let worstGap = gaps(in: meals).max(by: { $0.penalty < $1.penalty }) {
                for alternative in worstGap.closing(from: open).prefix(WeekPlanner.alternativesPerMove)
                where !alternatives.contains(where: { $0.recipeID == alternative.recipeID }) {
                    alternatives.append(alternative)
                }
            }
            if let first = original[meal.id], first.leftoverOf == nil, first.recipeID != meal.recipeID,
               let back = open.first(where: { $0.recipeID == first.recipeID }),
               !alternatives.contains(where: { $0.recipeID == back.recipeID }) {
                alternatives.append(back)
            }

            var best: (meals: [PlannedMeal], value: Evaluation)?
            for alternative in alternatives {
                let trial = swapping(meal, to: alternative)
                let value = evaluate(trial)
                guard value.nutritionCost < current.nutritionCost - 1e-9 || value.changed < current.changed else { continue }
                if value.objective > (best?.value.objective ?? current.objective) + 1e-9 { best = (trial, value) }
            }
            if let best {
                meals = best.meals
                current = best.value
            }
        }
    }

    /// `meals` with `meal` cooking `option` and its leftovers following; back to its original recipe it is unchanged.
    private func swapping(_ meal: PlannedMeal, to option: ScoredRecipe) -> [PlannedMeal] {
        meals.map { entry in
            var entry = entry
            if entry.id == meal.id {
                entry.recipeID = option.recipeID
                if let first = original[meal.id], first.recipeID == option.recipeID {
                    entry.reasonCodes = first.reasonCodes
                } else {
                    entry.reasonCodes = [.replacedBecause(cause: causes[meal.id] ?? .balance)] + option.reasonCodes
                }
            } else if entry.leftoverOf == meal.id, isEditable(entry) {
                entry.recipeID = option.recipeID
            }
            return entry
        }
    }

    // MARK: Verification

    /// Drops changed meals the verifier fails; returns the final report.
    mutating func backstop() -> VerificationReport {
        let failing = Set(verify(meals).hardViolations.map(\.plannedMealID))
        for meal in ordered(meals.filter { failing.contains($0.id) && isChanged($0) }) {
            remove(meal, cause: causes[meal.id] ?? .balance)
        }
        vacancies = []
        return verify(meals)
    }

    private func verify(_ meals: [PlannedMeal]) -> VerificationReport {
        PlanVerifier.verify(
            meals: meals,
            candidates: request.candidates,
            foods: request.context.foods,
            constraints: request.compiled.constraints,
            targets: request.compiled.targets,
            days: dates.count,
            householdSize: household,
            slots: Set(request.slots)
        )
    }

    // MARK: Options

    /// Admitted recipes for `meal`'s slot that the week can take, best first: within the cuisine quota, or all when none is.
    private func freshOptions(for meal: PlannedMeal, batch: Bool) -> [ScoredRecipe] {
        let available = pool.filter { isOpen($0, for: meal, batch: batch) }
        let withinQuota = available.filter { !breachesQuota($0, at: meal) }
        return withinQuota.isEmpty ? available : withinQuota
    }

    /// Admitted recipes for `meal`'s slot within the cuisine quota, best first; the search never adds a breach.
    private func openOptions(for meal: PlannedMeal, batch: Bool) -> [ScoredRecipe] {
        pool.filter { isOpen($0, for: meal, batch: batch) && !breachesQuota($0, at: meal) }
    }

    private mutating func pick(from options: [ScoredRecipe]) -> ScoredRecipe? {
        guard let best = options.first else { return nil }
        let band = options.prefix { $0.score >= best.score - WeekPlanner.greedyBand }
        return band[band.startIndex + Int(random.next(upperBound: UInt64(band.count)))]
    }

    private func isOpen(_ option: ScoredRecipe, for meal: PlannedMeal, batch: Bool) -> Bool {
        guard option.recipeID != meal.recipeID, option.candidate.fits(meal.slot), !retired.contains(option.recipeID),
              !batch || isBatch(option.recipeID), lostFood(in: option.candidate) == nil
        else { return false }
        return !meals.contains { $0.recipeID == option.recipeID && $0.id != meal.id && $0.leftoverOf != meal.id }
    }

    private func breachesQuota(_ option: ScoredRecipe, at meal: PlannedMeal) -> Bool {
        guard let cuisine = option.candidate.recipe.tags.cuisine?.lowercased() else { return false }
        let used = meals.count { entry in
            entry.id != meal.id && entry.slot == meal.slot && entry.leftoverOf == nil && entry.status != .skipped
                && day(of: entry.date).map { (0..<dates.count).contains($0) } == true
                && candidates[entry.recipeID]?.recipe.tags.cuisine?.lowercased() == cuisine
        }
        return used >= quota
    }

    private func isBatch(_ recipe: RecipeID) -> Bool {
        (candidates[recipe]?.recipe.servings ?? 0) >= household * 2
    }

    /// The first food, by identifier, that `candidate` needs from the lost foods and the pantry no longer holds.
    private func lostFood(in candidate: RecipeCandidate) -> FoodID? {
        let lost = events.ranOut.union(events.expired)
        guard !lost.isEmpty else { return nil }
        return candidate.ingredients
            .filter { !$0.isGarnish && !$0.isOptional }
            .compactMap(\.foodID)
            .filter { lost.contains($0) && available[$0] == nil }
            .min { $0.rawValue.uuidString < $1.rawValue.uuidString }
    }

    /// Whether the pantry holds every required line that names a food, in grams for the meal's servings when the
    /// line resolves to grams and at all when it does not.
    private func covers(_ meal: PlannedMeal) -> Bool {
        guard let candidate = candidates[meal.recipeID] else { return false }
        let factor = Double(meal.servings) / Double(max(candidate.recipe.servings, 1))
        var remaining = available
        for line in candidate.ingredients where !line.isGarnish && !line.isOptional {
            guard let foodID = line.foodID else { continue }
            guard let have = remaining[foodID], have > 0 else { return false }
            if let grams = IngredientGrams.resolve(line, food: request.context.foods[foodID]), grams.isFinite {
                let needed = grams * factor
                guard have + 1e-9 >= needed else { return false }
                remaining[foodID] = have - needed
            }
        }
        return true
    }

    // MARK: Reading the week

    private func day(of date: Date) -> Int? {
        if let day = dayByDate[date] { return day }
        let calendar = request.calendar
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: plan.startDate), to: calendar.startOfDay(for: date)).day
    }

    /// Planned, unlocked and on a plan day from today on.
    private func isEditable(_ meal: PlannedMeal) -> Bool {
        meal.status == .planned && !meal.isLocked
            && day(of: meal.date).map { $0 >= max(todayIndex, 0) && $0 < dates.count } == true
    }

    private func isFree(_ day: Int, _ slot: MealType, ignoring: Set<PlannedMealID>) -> Bool {
        isFree(day, slot, ignoring: ignoring, in: meals)
    }

    private func isFree(_ day: Int, _ slot: MealType, ignoring: Set<PlannedMealID>, in meals: [PlannedMeal]) -> Bool {
        guard (0..<dates.count).contains(day) else { return false }
        return !meals.contains { $0.slot == slot && !ignoring.contains($0.id) && self.day(of: $0.date) == day }
    }

    private func leftovers(of source: PlannedMealID, in meals: some Sequence<PlannedMeal>) -> [PlannedMeal] {
        meals.filter { $0.leftoverOf == source }
    }

    private func ordered(_ meals: [PlannedMeal]) -> [PlannedMeal] {
        meals.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            let left = MealType.allCases.firstIndex(of: lhs.slot) ?? 0
            let right = MealType.allCases.firstIndex(of: rhs.slot) ?? 0
            if left != right { return left < right }
            return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
        }
    }

    /// Whether `meal` differs from the plan as made in recipe or day.
    private func isChanged(_ meal: PlannedMeal) -> Bool {
        guard let first = original[meal.id] else { return true }
        return first.recipeID != meal.recipeID || first.date != meal.date
    }

    // MARK: Objective

    private func gaps(in meals: [PlannedMeal]) -> [NutrientGap] {
        bands(in: meals).gaps
    }

    /// Nutrients with a band the data covers that `meals` sit inside.
    private func metBands(in meals: [PlannedMeal]) -> Set<Nutrient> {
        bands(in: meals).met
    }

    /// The nutrients outside their bands and the nutrients inside them, from one pass over the meals.
    private func bands(in meals: [PlannedMeal]) -> (gaps: [NutrientGap], met: Set<Nutrient>) {
        let totals = PlanNutrition(meals: meals, candidates: candidates)
        let targets = request.compiled.targets
        let gaps = NutrientGap.gaps(in: totals, targets: targets, days: dates.count, householdSize: household, coverage: coverage)
        let outside = Set(gaps.map(\.nutrient))
        let met = Set(targets.compactMap { target -> Nutrient? in
            guard totals.perPersonPerDay(target.nutrient, days: dates.count, householdSize: household) != nil,
                  totals.dailyBand(for: target, days: dates.count, householdSize: household, coverage: coverage) != nil,
                  !outside.contains(target.nutrient)
            else { return nil }
            return target.nutrient
        })
        return (gaps, met)
    }

    private func breakdown(_ meals: [PlannedMeal]) -> PlanScoreBreakdown {
        breakdown(meals, gaps: gaps(in: meals))
    }

    private func breakdown(_ meals: [PlannedMeal], gaps: [NutrientGap]) -> PlanScoreBreakdown {
        let mealScore = meals.reduce(0) { total, meal in
            meal.leftoverOf == nil && meal.status != .skipped ? total + (scores[meal.recipeID]?.score ?? 0) : total
        }
        let nutrientPenalty = gaps.reduce(0) { $0 + $1.penalty }
        let varietyPenalty = WeekPlanner.quotaPenalty * Double(quotaViolations(in: meals))
        return PlanScoreBreakdown(
            mealScoreTotal: mealScore,
            nutrientPenalty: nutrientPenalty,
            varietyPenalty: varietyPenalty,
            objective: mealScore - nutrientPenalty - varietyPenalty
        )
    }

    /// How the search weighs a week.
    private struct Evaluation {
        /// The plan objective less the change and lost-band penalties.
        var objective: Double
        /// The nutrient penalty plus the lost-band penalty.
        var nutritionCost: Double
        /// Meals that differ from the plan as made, removed ones included; a leftover that only follows its changed
        /// cooked meal is part of that one change.
        var changed: Int
    }

    private func evaluate(_ meals: [PlannedMeal]) -> Evaluation {
        let byID = Dictionary(meals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let changed = meals.count { meal in
            guard isChanged(meal) else { return false }
            guard let source = meal.leftoverOf.flatMap({ byID[$0] }), let first = original[meal.id] else { return true }
            return first.leftoverOf != source.id || first.date != meal.date || source.recipeID != meal.recipeID || !isChanged(source)
        } + original.keys.count { byID[$0] == nil }
        let bands = bands(in: meals)
        let lostPenalty = PlanRepairer.bandPenalty * Double(baselineBands.subtracting(bands.met).count)
        let breakdown = breakdown(meals, gaps: bands.gaps)
        return Evaluation(
            objective: breakdown.objective - PlanRepairer.changePenalty * Double(changed) - lostPenalty,
            nutritionCost: breakdown.nutrientPenalty + lostPenalty,
            changed: changed
        )
    }

    private func quotaViolations(in meals: [PlannedMeal]) -> Int {
        var counts: [String: Int] = [:]
        for meal in meals where meal.leftoverOf == nil && meal.status != .skipped {
            guard day(of: meal.date).map({ (0..<dates.count).contains($0) }) == true,
                  let cuisine = candidates[meal.recipeID]?.recipe.tags.cuisine?.lowercased()
            else { continue }
            counts["\(meal.slot.rawValue)|\(cuisine)", default: 0] += 1
        }
        return counts.values.reduce(0) { $0 + max($1 - quota, 0) }
    }

    // MARK: Result

    func repair(verification: VerificationReport) -> PlanRepair {
        let final = ordered(meals)
        let byID = Dictionary(final.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [PlanChange] = []
        for first in original.values {
            let cause = causes[first.id] ?? .balance
            guard let meal = byID[first.id] else {
                changes.append(PlanChange(mealID: first.id, date: first.date, slot: first.slot, recipeID: first.recipeID, action: .removed, cause: cause))
                continue
            }
            if meal.recipeID != first.recipeID {
                changes.append(PlanChange(
                    mealID: meal.id, date: meal.date, slot: meal.slot, recipeID: meal.recipeID,
                    action: .replaced(previous: first.recipeID), cause: cause
                ))
            } else if meal.date != first.date {
                changes.append(PlanChange(
                    mealID: meal.id, date: meal.date, slot: meal.slot, recipeID: meal.recipeID,
                    action: .moved(from: first.date), cause: cause
                ))
            }
        }
        changes.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            let left = MealType.allCases.firstIndex(of: lhs.slot) ?? 0
            let right = MealType.allCases.firstIndex(of: rhs.slot) ?? 0
            if left != right { return left < right }
            return lhs.mealID.rawValue.uuidString < rhs.mealID.rawValue.uuidString
        }

        var types: [MealType] = []
        for type in request.slots where !types.contains(type) { types.append(type) }
        let unfilled = (max(todayIndex, 0)..<max(dates.count, max(todayIndex, 0))).flatMap { day in
            types.filter { isFree(day, $0, ignoring: [], in: final) }.map { (date: dates[day], slot: $0) }
        }
        return PlanRepair(
            result: PlanResult(plan: plan, meals: final, unfilledSlots: unfilled, breakdown: breakdown(final), verification: verification),
            changes: changes
        )
    }
}
