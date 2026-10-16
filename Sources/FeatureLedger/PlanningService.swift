import Foundation
import LarderCore

/// Recipes as planner candidates together with the foods their lines reference.
public nonisolated struct PlanningCatalogue: Sendable {
    public var candidates: [RecipeCandidate]
    public var foods: [FoodID: Food]

    /// Creates a catalogue.
    public init(candidates: [RecipeCandidate], foods: [FoodID: Food]) {
        self.candidates = candidates
        self.foods = foods
    }
}

/// Orchestrates the Core planning pipeline over the repositories; holds no state of its own.
public nonisolated struct PlanningService: Sendable {
    /// Days in a generated plan.
    public static let weekDays = 7
    /// Days of history that lower a recipe's novelty.
    static let recentDays = 28
    /// Days within which a cuisine counts as already eaten this week.
    static let recentCuisineDays = 7
    /// Skips of the same recipe after which it counts as disliked.
    static let skipsToDislike = 2

    private let plans: any PlanRepository
    private let recipes: any RecipeRepository
    private let foods: any FoodRepository
    private let pantry: any PantryRepository
    private let profiles: any ProfileRepository
    private let dates: any DateProvider
    private let calendar: Calendar

    /// Creates a service over the given ports; `calendar` steps days and decides what counts as the same day.
    public init(
        plans: any PlanRepository,
        recipes: any RecipeRepository,
        foods: any FoodRepository,
        pantry: any PantryRepository,
        profiles: any ProfileRepository,
        dates: any DateProvider,
        calendar: Calendar = .current
    ) {
        self.plans = plans
        self.recipes = recipes
        self.foods = foods
        self.pantry = pantry
        self.profiles = profiles
        self.dates = dates
        self.calendar = calendar
    }

    /// Every stored recipe as a candidate, with its ingredient lines and referenced foods.
    public func candidates() async throws -> [RecipeCandidate] {
        try await catalogue().candidates
    }

    /// Candidates for the given recipes, or for every recipe when `ids` is `nil`; unknown identifiers are skipped.
    public func catalogue(for ids: Set<RecipeID>? = nil) async throws -> PlanningCatalogue {
        let recipeList: [Recipe]
        if let ids {
            var found: [Recipe] = []
            for id in ids.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
                if let recipe = try await recipes.recipe(by: id) { found.append(recipe) }
            }
            recipeList = found
        } else {
            recipeList = try await recipes.all()
        }
        var lines: [RecipeID: [Ingredient]] = [:]
        for recipe in recipeList {
            lines[recipe.id] = try await recipes.ingredients(for: recipe.id)
        }
        let foodIDs = Set(lines.values.joined().compactMap(\.foodID))
        let foodList = try await foods.foods(byIDs: Array(foodIDs))
        let foodsByID = Dictionary(foodList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return PlanningCatalogue(
            candidates: CandidateBuilder.build(recipes: recipeList, ingredients: lines, foods: foodsByID),
            foods: foodsByID
        )
    }

    /// What the scorer knows: recency from the last 28 days, cuisines from the last 7, liked from cooked meals
    /// and skipped from recipes skipped at least twice in `recentPlans`.
    public func context(
        for profile: UserProfile,
        pantry: [PantryItem],
        recentPlans: [PlannedMeal],
        catalogue: PlanningCatalogue
    ) -> ScoringContext {
        let now = dates.now
        let recentStart = calendar.date(byAdding: .day, value: -Self.recentDays, to: now) ?? now
        let cuisineStart = calendar.date(byAdding: .day, value: -Self.recentCuisineDays, to: now) ?? now
        let cuisines = Dictionary(
            catalogue.candidates.compactMap { candidate in candidate.recipe.tags.cuisine.map { (candidate.recipe.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )

        var recentlyPlanned: [RecipeID: Date] = [:]
        var recentCuisines: [String: Date] = [:]
        var liked = Set<RecipeID>()
        var skips: [RecipeID: Int] = [:]
        for meal in recentPlans {
            if meal.date > recentStart, meal.date <= now {
                recentlyPlanned[meal.recipeID] = max(recentlyPlanned[meal.recipeID] ?? meal.date, meal.date)
                if meal.date > cuisineStart, let cuisine = cuisines[meal.recipeID] {
                    let key = cuisine.lowercased()
                    recentCuisines[key] = max(recentCuisines[key] ?? meal.date, meal.date)
                }
            }
            switch meal.status {
            case .cooked: liked.insert(meal.recipeID)
            case .skipped: skips[meal.recipeID, default: 0] += 1
            case .planned: break
            }
        }

        return ScoringContext(
            pantry: pantry,
            foods: catalogue.foods,
            now: now,
            recentlyPlanned: recentlyPlanned,
            recentCuisines: recentCuisines,
            liked: liked,
            skipped: Set(skips.filter { $0.value >= Self.skipsToDislike }.keys),
            goal: profile.goal,
            maxCookMinutes: profile.maxCookMinutes,
            weeklyBudget: profile.weeklyBudget
        )
    }

    /// Hard filters and planning inputs for `profile`.
    public func compiled(profile: UserProfile, constraints: [DietaryConstraint], targets: [NutrientTarget]) -> CompiledConstraints {
        ConstraintCompiler.compile(profile: profile, constraints: constraints, targets: targets)
    }

    /// Solves a week from `startDate`; `locked` meals are kept as given when their date falls inside it.
    public func planWeek(startDate: Date, slots: [MealType] = [.dinner], seed: UInt64, locked: [PlannedMeal]) async throws -> PlanResult {
        let catalogue = try await catalogue()
        let inputs = try await inputs(catalogue: catalogue)
        return WeekPlanner.plan(
            PlanRequest(
                startDate: startDate,
                days: Self.weekDays,
                slots: slots,
                candidates: catalogue.candidates,
                compiled: inputs.compiled,
                context: inputs.context,
                lockedMeals: locked,
                seed: seed,
                calendar: calendar
            )
        )
    }

    /// Up to `limit` pantry-first dinner options for tonight, best first.
    public func tonight(limit: Int = 3) async throws -> [ScoredRecipe] {
        let catalogue = try await catalogue()
        let inputs = try await inputs(catalogue: catalogue)
        return TonightPicker.pick(
            candidates: catalogue.candidates,
            admission: { inputs.compiled.admits($0, foods: catalogue.foods) },
            context: inputs.context,
            limit: limit
        )
    }

    /// Replacement recipes for `meal`, best first, excluding recipes already in `meals`.
    public func swapCandidates(for meal: PlannedMeal, in meals: [PlannedMeal], limit: Int = 5) async throws -> [ScoredRecipe] {
        let catalogue = try await catalogue()
        let inputs = try await inputs(catalogue: catalogue)
        let result = PlanResult(
            plan: MealPlan(
                id: meal.planID,
                startDate: meal.date,
                days: 0,
                constraintsSnapshot: inputs.compiled.snapshot,
                solverVersion: WeekPlanner.solverVersion,
                seed: 0,
                status: .draft
            ),
            meals: meals,
            unfilledSlots: [],
            breakdown: PlanScoreBreakdown(mealScoreTotal: 0, nutrientPenalty: 0, varietyPenalty: 0, objective: 0),
            verification: VerificationReport(hardViolations: [], nutrientNotes: [], shelfBalance: ShelfBalance(levels: [:]))
        )
        return SwapSuggester.suggest(
            for: meal,
            in: result,
            candidates: catalogue.candidates,
            admission: { inputs.compiled.admits($0, foods: catalogue.foods) },
            context: inputs.context,
            limit: limit
        )
    }

    /// Re-checks `meals` with the plan verifier against the stored profile, constraints and targets.
    public func verify(meals: [PlannedMeal], days: Int, catalogue: PlanningCatalogue) async throws -> VerificationReport {
        let (profile, constraints, targets) = try await profileInputs()
        return PlanVerifier.verify(
            meals: meals,
            candidates: catalogue.candidates,
            foods: catalogue.foods,
            constraints: constraints,
            targets: targets,
            days: days,
            householdSize: profile.householdSize,
            slots: Set(meals.map(\.slot))
        )
    }

    // MARK: Inputs

    private struct Inputs {
        var compiled: CompiledConstraints
        var context: ScoringContext
    }

    private func inputs(catalogue: PlanningCatalogue) async throws -> Inputs {
        let (profile, constraints, targets) = try await profileInputs()
        let shelves = try await pantry.items()
        let recent = try await recentMeals()
        return Inputs(
            compiled: compiled(profile: profile, constraints: constraints, targets: targets),
            context: context(for: profile, pantry: shelves, recentPlans: recent, catalogue: catalogue)
        )
    }

    /// The profile, constraints and targets; stored targets win, otherwise the defaults for this year.
    private func profileInputs() async throws -> (UserProfile, [DietaryConstraint], [NutrientTarget]) {
        guard let profile = try await profiles.profile() else { throw LarderError.notFound }
        let constraints = try await profiles.constraints()
        let stored = try await profiles.targets()
        let targets = stored.isEmpty
            ? NutrientTargets.defaults(for: profile, constraints: constraints, referenceYear: calendar.component(.year, from: dates.now))
            : stored
        return (profile, constraints, targets)
    }

    /// Meals of every plan that reaches into the recency window.
    private func recentMeals() async throws -> [PlannedMeal] {
        let now = dates.now
        let windowStart = calendar.date(byAdding: .day, value: -Self.recentDays, to: now) ?? now
        var meals: [PlannedMeal] = []
        for plan in try await plans.plans() {
            let end = calendar.date(byAdding: .day, value: plan.days, to: plan.startDate) ?? plan.startDate
            guard end > windowStart, plan.startDate <= now else { continue }
            meals += try await plans.meals(for: plan.id)
        }
        return meals
    }
}
