import Foundation
@_spi(Bench) import LarderCore

/// What every arm sees when it plans one household's week; identical across arms for the same household and week.
struct WeekInput: Sendable {
    var household: Household
    var week: Int
    var startDate: Date
    var days: Int
    var slots: [MealType]
    var candidates: [RecipeCandidate]
    var compiled: CompiledConstraints
    /// Built from the household's real pantry and history, as `PlanningService.context` builds it in the app.
    var context: ScoringContext
    var seed: UInt64
    var planID: MealPlanID
    var calendar: Calendar

    var request: PlanRequest {
        PlanRequest(
            startDate: startDate, days: days, slots: slots, candidates: candidates, compiled: compiled,
            context: context, seed: seed, planID: planID, calendar: calendar
        )
    }

    var dates: [Date] {
        (0..<days).map { calendar.date(byAdding: .day, value: $0, to: startDate) ?? startDate }
    }
}

/// One arm's week: meals in day order and the number of slots left empty.
struct WeekPlan: Sendable {
    var meals: [PlannedMeal]
    var unfilledSlots: Int
}

/// A way of producing a week of meals; every arm is scored by the same simulation and metrics.
protocol Arm: Sendable {
    var name: String { get }
    func plan(_ input: WeekInput) -> WeekPlan
}

/// The shipped planner: seeded greedy fill, local search, verification and repair.
struct PlannerArm: Arm {
    var name: String { "planner" }

    func plan(_ input: WeekInput) -> WeekPlan {
        let result = WeekPlanner.plan(input.request)
        return WeekPlan(meals: result.meals, unfilledSlots: result.unfilledSlots.count)
    }
}

/// The planner's own greedy fill and repair with the local search switched off (`WeekPlanner.planWithoutSearch`).
struct GreedyArm: Arm {
    var name: String { "greedy" }

    func plan(_ input: WeekInput) -> WeekPlan {
        let result = WeekPlanner.planWithoutSearch(input.request)
        return WeekPlan(meals: result.meals, unfilledSlots: result.unfilledSlots.count)
    }
}

/// The full planner blind to the pantry: it scores against an empty pantry and no use-up list.
///
/// `RecipeScorer`'s pantry overlap, expiry urgency and cost proxy are all functions of the pantry, so with an empty
/// pantry each is 0 for every recipe: the same ranking as setting those three weights to zero, without touching the
/// scorer. The simulation still shops and cooks against the household's real pantry.
struct NoPantryArm: Arm {
    var name: String { "no-pantry" }

    func plan(_ input: WeekInput) -> WeekPlan {
        var request = input.request
        request.context.pantry = []
        request.context.useUp = []
        let result = WeekPlanner.plan(request)
        return WeekPlan(meals: result.meals, unfilledSlots: result.unfilledSlots.count)
    }
}

/// Uniformly random admitted recipes, without repeats inside the week while any unused recipe fits; no leftovers.
struct RandomArm: Arm {
    var name: String { "random" }

    func plan(_ input: WeekInput) -> WeekPlan {
        var draws = Draws(seed: SeedMix.mix(input.seed, 0x5241_4E44))
        let admitted = input.candidates.filter { candidate in
            if case .admitted = input.compiled.admits(candidate, foods: input.context.foods) { true } else { false }
        }
        var meals: [PlannedMeal] = []
        var unfilled = 0
        var used = Set<RecipeID>()
        for date in input.dates {
            for slot in input.slots {
                let fitting = admitted.filter { $0.fits(slot) }
                let fresh = fitting.filter { !used.contains($0.recipe.id) }
                let options = fresh.isEmpty ? fitting : fresh
                guard !options.isEmpty else {
                    unfilled += 1
                    continue
                }
                let choice = draws.element(of: options)
                used.insert(choice.recipe.id)
                meals.append(PlannedMeal(
                    planID: input.planID, date: date, slot: slot, recipeID: choice.recipe.id,
                    servings: input.compiled.householdSize
                ))
            }
        }
        return WeekPlan(meals: meals, unfilledSlots: unfilled)
    }
}

/// Plans produced elsewhere, for example by the assistant proxy, read from a JSON file and scored like any arm.
///
/// The file holds one entry per household and week, matched by `household` index and zero-based `week`:
///
/// ```json
/// {"plans": [{"household": 0, "week": 0, "meals": [
///     {"day": 0, "slot": "dinner", "recipe": "weeknight-chana-masala", "servings": 2},
///     {"day": 1, "slot": "dinner", "recipe": "weeknight-chana-masala", "servings": 2, "leftoverOfDay": 0}
/// ]}]}
/// ```
///
/// Recipes are seed slugs; an unknown slug keeps its slug-derived identifier, so the verifier reports it as a hard
/// violation ("No recipe data") instead of the harness dropping it. A household and week without an entry plans
/// nothing, so every slot counts as unfilled. The plans are fixed in advance (open loop): they cannot react to the
/// pantry the simulation produces, which `--export-households` writes out as the starting state for the generator.
struct FileArm: Arm {
    struct File: Codable, Sendable {
        var plans: [Entry]
    }

    struct Entry: Codable, Sendable {
        var household: Int
        var week: Int
        var meals: [Meal]
    }

    struct Meal: Codable, Sendable {
        var day: Int
        var slot: MealType
        var recipe: String
        var servings: Int?
        /// The day whose meal (same slot) this one is a leftover of.
        var leftoverOfDay: Int?
    }

    let name: String
    let plans: [String: [Meal]]
    let recipeIDs: [String: RecipeID]

    init(name: String = "llm", file: File, catalogue: SeedCatalogue) {
        self.name = name
        plans = Dictionary(file.plans.map { ("\($0.household)/\($0.week)", $0.meals) }, uniquingKeysWith: { first, _ in first })
        recipeIDs = catalogue.recipeIDsBySlug
    }

    static func load(from url: URL, catalogue: SeedCatalogue) throws -> FileArm {
        FileArm(file: try JSONDecoder().decode(File.self, from: Data(contentsOf: url)), catalogue: catalogue)
    }

    func plan(_ input: WeekInput) -> WeekPlan {
        let dates = input.dates
        let entries = (plans["\(input.household.index)/\(input.week)"] ?? [])
            .filter { dates.indices.contains($0.day) && input.slots.contains($0.slot) }
            .sorted { ($0.day, $0.slot.order) < ($1.day, $1.slot.order) }
        var meals: [PlannedMeal] = []
        var bySlot: [String: PlannedMeal] = [:]
        for entry in entries where bySlot["\(entry.day)/\(entry.slot.rawValue)"] == nil {
            let source = entry.leftoverOfDay.flatMap { bySlot["\($0)/\(entry.slot.rawValue)"] }
            let meal = PlannedMeal(
                planID: input.planID,
                date: dates[entry.day],
                slot: entry.slot,
                recipeID: recipeIDs[entry.recipe] ?? RecipeID(rawValue: SeedCatalogue.uuid(for: entry.recipe)),
                servings: max(entry.servings ?? input.compiled.householdSize, 1),
                leftoverOf: source?.id
            )
            bySlot["\(entry.day)/\(entry.slot.rawValue)"] = meal
            meals.append(meal)
        }
        return WeekPlan(meals: meals, unfilledSlots: dates.count * Set(input.slots).count - meals.count)
    }
}

extension MealType {
    /// Position in the day, for sorting.
    var order: Int { MealType.allCases.firstIndex(of: self) ?? 0 }
}
