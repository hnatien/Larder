import Foundation

/// A planned meal that breaks a hard rule.
public struct Violation: Hashable, Sendable {
    public var plannedMealID: PlannedMealID
    public var recipeID: RecipeID
    /// Ready-to-show reasons.
    public var reasons: [String]

    /// Creates a violation.
    public init(plannedMealID: PlannedMealID, recipeID: RecipeID, reasons: [String]) {
        self.plannedMealID = plannedMealID
        self.recipeID = recipeID
        self.reasons = reasons
    }
}

/// Where a plan's daily amount of a nutrient sits against its target band.
public enum NutrientStatus: String, Hashable, Sendable {
    case under
    case within
    case over
}

/// One nutrient's daily amount per person against its band, both in the nutrient's own unit.
///
/// Per-day bands are scaled by the report's `coverage`, so a dinner-only plan is held to a dinner's share.
public struct NutrientNote: Hashable, Sendable {
    public var nutrient: Nutrient
    public var totalPerDay: Double
    /// Lower bound per person per day; a target without a range uses its target amount as the floor.
    public var min: Double?
    /// Upper bound per person per day.
    public var max: Double?
    public var status: NutrientStatus

    /// Creates a note.
    public init(nutrient: Nutrient, totalPerDay: Double, min: Double?, max: Double?, status: NutrientStatus) {
        self.nutrient = nutrient
        self.totalPerDay = totalPerDay
        self.min = min
        self.max = max
        self.status = status
    }
}

/// What the verifier found; this is what the UI shows as "why".
public struct VerificationReport: Hashable, Sendable {
    public var hardViolations: [Violation]
    public var nutrientNotes: [NutrientNote]
    public var shelfBalance: ShelfBalance
    /// The share of a day's eating the plan's meal slots cover (see `MealSlotShare`); 0.35 reads as "for dinners".
    public var coverage: Double

    /// Creates a report.
    public init(hardViolations: [Violation], nutrientNotes: [NutrientNote], shelfBalance: ShelfBalance, coverage: Double = 1) {
        self.hardViolations = hardViolations
        self.nutrientNotes = nutrientNotes
        self.shelfBalance = shelfBalance
        self.coverage = coverage
    }
}

/// Re-checks a finished plan on its own path, without trusting earlier admission results.
public enum PlanVerifier {
    /// Every meal is re-run through the allergen engine and the constraint filter; excluded and uncertain
    /// verdicts are both hard violations, as is a meal whose recipe is missing from `candidates`.
    ///
    /// Nutrient notes cover per-day and per-1,000-kcal targets, per person per day; other bases are skipped,
    /// as are nutrients the food data does not cover. Per-day bands, maxima included, are scaled to the share
    /// of the day that `slots` cover.
    public static func verify(
        meals: [PlannedMeal],
        candidates: [RecipeCandidate],
        foods: [FoodID: Food],
        constraints: [DietaryConstraint],
        targets: [NutrientTarget],
        days: Int,
        householdSize: Int,
        slots: Set<MealType> = Set(MealType.allCases)
    ) -> VerificationReport {
        let byID = Dictionary(candidates.map { ($0.recipe.id, $0) }, uniquingKeysWith: { first, _ in first })
        let violations = meals.compactMap { meal -> Violation? in
            guard let candidate = byID[meal.recipeID] else {
                return Violation(plannedMealID: meal.id, recipeID: meal.recipeID, reasons: ["No recipe data, so it cannot be checked"])
            }
            let reasons = hardReasons(for: candidate, foods: foods, constraints: constraints)
            return reasons.isEmpty ? nil : Violation(plannedMealID: meal.id, recipeID: meal.recipeID, reasons: reasons)
        }

        let totals = PlanNutrition(meals: meals, candidates: byID)
        let coverage = MealSlotShare.coverage(slots: slots)
        return VerificationReport(
            hardViolations: violations,
            nutrientNotes: notes(totals: totals, targets: targets, days: days, householdSize: householdSize, coverage: coverage),
            shelfBalance: ShelfBalanceCalculator.balance(meals: totals.shelfMeals, days: days),
            coverage: coverage
        )
    }

    private static func hardReasons(for candidate: RecipeCandidate, foods: [FoodID: Food], constraints: [DietaryConstraint]) -> [String] {
        var reasons: [String] = []
        let lines = candidate.ingredients
        switch AllergenEngine().evaluate(recipe: candidate.recipe, ingredients: lines, foods: foods, constraints: constraints) {
        case .clear: break
        case .excluded(let found), .uncertain(let found): reasons += found.map { describe($0, lines: lines, foods: foods) }
        }
        switch ConstraintFilter().verdict(recipe: candidate.recipe, ingredients: lines, foods: foods, constraints: constraints) {
        case .pass: break
        case .excluded(let found), .uncertain(let found): reasons += found
        }
        var seen = Set<String>()
        return reasons.filter { seen.insert($0).inserted }
    }

    private static func describe(_ reason: AllergenReason, lines: [Ingredient], foods: [FoodID: Food]) -> String {
        let allergen = reason.allergen.readableName
        let line = reason.ingredientID.flatMap { id in lines.first { $0.id == id } }
        let place = line.map { line in line.foodID.flatMap { foods[$0]?.name } ?? line.rawText } ?? "recipe"
        switch reason.evidence {
        case .lexicon(let term): return "Contains \(allergen) (\(term))"
        case .dataTag(.contains): return "Contains \(allergen) (\(place))"
        case .dataTag(.mayContain): return "May contain \(allergen) (\(place))"
        case .dataTag(.unknown): return "No \(allergen) data (\(place))"
        case .dataTag(.verifiedFree): return "Free of \(allergen) (\(place))"
        }
    }

    private static func notes(
        totals: PlanNutrition,
        targets: [NutrientTarget],
        days: Int,
        householdSize: Int,
        coverage: Double
    ) -> [NutrientNote] {
        targets.compactMap { target in
            guard let perDay = totals.perPersonPerDay(target.nutrient, days: days, householdSize: householdSize),
                  let band = totals.dailyBand(
                      for: target, days: days, householdSize: householdSize, coverage: coverage, targetAsFloor: true
                  )
            else { return nil }
            let status: NutrientStatus = if let low = band.min, perDay < low {
                .under
            } else if let high = band.max, perDay > high {
                .over
            } else {
                .within
            }
            return NutrientNote(nutrient: target.nutrient, totalPerDay: perDay, min: band.min, max: band.max, status: status)
        }
    }
}

/// Nutrients actually eaten over a plan, shared by the verifier and the planner objective.
///
/// A leftover whose source meal is in the plan adds nothing, because the source meal's servings already
/// include it; skipped meals add nothing either.
struct PlanNutrition {
    /// Household total.
    var total = Nutrients()
    var shelfMeals: [(RecipeNutrition, servings: Int, groups: [FoodGroup: Double])] = []

    init(meals: [PlannedMeal], candidates: [RecipeID: RecipeCandidate]) {
        let mealIDs = Set(meals.map(\.id))
        for meal in meals where meal.status != .skipped && meal.servings > 0 {
            if let source = meal.leftoverOf, mealIDs.contains(source) { continue }
            guard let candidate = candidates[meal.recipeID] else { continue }
            total = total + candidate.nutrition.perServing.scaled(by: Double(meal.servings))
            let factor = Double(meal.servings) / Double(max(candidate.recipe.servings, 1))
            shelfMeals.append((candidate.nutrition, meal.servings, candidate.foodGroupsGrams.mapValues { $0 * factor }))
        }
    }

    /// Amount of `nutrient` per person per day, or `nil` when unknown or `days` is not positive.
    func perPersonPerDay(_ nutrient: Nutrient, days: Int, householdSize: Int) -> Double? {
        guard days > 0, let value = total.value(of: nutrient), value.isFinite else { return nil }
        return value / Double(days) / Double(max(householdSize, 1))
    }

    /// The target's band per person per day; per-day bands scale by `coverage`, the share of the day the
    /// plan's slots cover, and per-1,000-kcal bands by the plan's energy.
    ///
    /// Without `targetAsFloor` only explicit min and max count; with it, a target that has neither uses
    /// its target amount as the floor. `nil` for other bases, unknown energy, no coverage, or no bound at all.
    func dailyBand(
        for target: NutrientTarget,
        days: Int,
        householdSize: Int,
        coverage: Double,
        targetAsFloor: Bool
    ) -> (min: Double?, max: Double?)? {
        let scale: Double
        switch target.basis {
        case .perDay:
            guard coverage > 0 else { return nil }
            scale = coverage
        case .per1000kcal:
            guard let kcal = perPersonPerDay(.energy, days: days, householdSize: householdSize), kcal > 0 else { return nil }
            scale = kcal / 1000
        case .perMeal, .percentEnergy:
            return nil
        }
        let low = target.min ?? (targetAsFloor && target.max == nil ? target.target : nil)
        guard low != nil || target.max != nil else { return nil }
        return (low.map { $0 * scale }, target.max.map { $0 * scale })
    }
}

extension Nutrients {
    /// The amount recorded for `nutrient`.
    func value(of nutrient: Nutrient) -> Double? {
        switch nutrient {
        case .energy: energyKcal
        case .protein: proteinG
        case .fat: fatG
        case .saturatedFat: saturatedFatG
        case .monounsaturatedFat: monounsaturatedFatG
        case .polyunsaturatedFat: polyunsaturatedFatG
        case .carbohydrate: carbohydrateG
        case .fiber: fiberG
        case .totalSugar: totalSugarG
        case .addedSugar: addedSugarG
        case .sodium: sodiumMg
        case .potassium: potassiumMg
        case .calcium: calciumMg
        case .iron: ironMg
        case .vitaminD: vitaminDMcg
        case .vitaminB12: vitaminB12Mcg
        }
    }
}
