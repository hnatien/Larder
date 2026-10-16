import Foundation
import LarderCore
import Observation

/// Tonight's dinner as the plan has it.
public struct TonightDinner: Equatable, Sendable {
    public var recipeID: RecipeID
    public var title: String
    public var minutes: Int
    /// The recipe's photo in the photo store, if it has one.
    public var photoFileName: String?
}

/// Drives the Tonight tab: tonight's planned dinner, and pantry-first ideas three at a time, offline and deterministic.
@Observable
@MainActor
public final class TonightModel {
    /// How many ideas Tonight shows at once.
    static let optionLimit = 3
    /// How many ideas "Show other ideas" can page through.
    static let poolLimit = 9
    /// Written to `MealPlan.solverVersion` for a plan made from Tonight rather than the planner.
    static let manualSolverVersion = "manual"

    /// Every idea found, best first; `options` shows one page of them.
    public private(set) var pool: [ScoredRecipe] = []
    /// Which page of `pool` is showing.
    public private(set) var page = 0
    /// Whether the shelves hold nothing, so there is nothing to cook from.
    public private(set) var shelvesAreEmpty = false
    public private(set) var isLoading = false
    public private(set) var error: LarderError?
    /// Tonight's dinner in the current plan, when there is one and it is not skipped.
    public private(set) var dinner: TonightDinner?
    private var foodsByID: [FoodID: Food] = [:]

    private let plans: any PlanRepository
    private let recipes: any RecipeRepository
    private let foods: any FoodRepository
    private let pantry: any PantryRepository
    private let profiles: any ProfileRepository
    private let service: PlanningService
    private let dates: any DateProvider
    private let calendar: Calendar

    /// Creates a model over the given ports; `calendar` decides which day is today.
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
        self.service = PlanningService(
            plans: plans, recipes: recipes, foods: foods, pantry: pantry, profiles: profiles, dates: dates, calendar: calendar
        )
    }

    /// Every idea except tonight's planned dinner, which has its own card.
    private var ideas: [ScoredRecipe] {
        pool.filter { $0.recipeID != dinner?.recipeID }
    }

    /// The ideas on show: up to three from the current page.
    public var options: [ScoredRecipe] {
        Array(ideas.dropFirst(page * Self.optionLimit).prefix(Self.optionLimit))
    }

    /// Whether there are more ideas than fit on one page.
    public var hasOtherIdeas: Bool { ideas.count > Self.optionLimit }

    /// The recipe ID of tonight's dinner, if one is planned.
    public var cookingID: RecipeID? { dinner?.recipeID }

    /// Loads tonight's dinner, up to nine ideas best first, and whether the shelves are empty.
    public func load() async {
        error = nil
        isLoading = true
        defer { isLoading = false }
        do {
            shelvesAreEmpty = try await pantry.items().isEmpty
            dinner = try await loadDinner()
            let found = try await service.tonight(limit: Self.poolLimit)
            let foodIDs = Set(found.flatMap(\.reasonCodes).compactMap { code -> FoodID? in
                if case .usesExpiring(let food, _) = code { food } else { nil }
            })
            let named = try await foods.foods(byIDs: Array(foodIDs))
            foodsByID = Dictionary(named.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            pool = found
            if page * Self.optionLimit >= ideas.count { page = 0 }
        } catch {
            record(error)
        }
    }

    /// Shows the next three ideas, wrapping back to the best ones after the last page.
    public func showOtherIdeas() {
        guard hasOtherIdeas else { return }
        let pages = (ideas.count + Self.optionLimit - 1) / Self.optionLimit
        page = (page + 1) % pages
    }

    /// Puts `option` on today's dinner: in the active plan when it covers today, otherwise in a new one-day plan.
    public func cookTonight(_ option: ScoredRecipe) async {
        await schedule(option, on: dates.now)
    }

    /// Puts `option` on `day`'s dinner. The active plan takes it when it covers the day, and is lengthened when it covers
    /// today but ends before the day; otherwise a stale plan is archived and a new one runs from today to the day.
    public func schedule(_ option: ScoredRecipe, on day: Date) async {
        error = nil
        do {
            let today = calendar.startOfDay(for: dates.now)
            let target = max(calendar.startOfDay(for: day), today)
            if let current = try await plans.currentPlan(), covers(current, today) {
                let plan = try await lengthen(current, toCover: target)
                try await put(option, on: target, in: plan)
            } else {
                try await startPlan(from: today, through: target, with: option)
            }
            if calendar.isDate(target, inSameDayAs: today) {
                dinner = TonightDinner(
                    recipeID: option.recipeID,
                    title: option.candidate.recipe.title,
                    minutes: option.candidate.totalMinutes,
                    photoFileName: option.candidate.recipe.photoFileName
                )
            }
        } catch {
            record(error)
        }
    }

    /// Reason lines for an idea, from its reason codes.
    public func reasons(for option: ScoredRecipe, limit: Int = .max) -> [String] {
        ReasonCopy.lines(
            for: option.reasonCodes,
            lookup: ReasonCopy.Lookup(foodNames: foodsByID.mapValues(\.name), calendar: calendar),
            limit: limit
        )
    }

    /// Clears the current error.
    public func clearError() {
        error = nil
    }

    /// Today's dinner in the active plan, skipping a skipped one.
    private func loadDinner() async throws -> TonightDinner? {
        let today = calendar.startOfDay(for: dates.now)
        guard let plan = try await plans.currentPlan(), covers(plan, today) else { return nil }
        let meals = try await plans.meals(for: plan.id)
        guard let meal = meals.first(where: {
            $0.slot == .dinner && $0.status != .skipped && calendar.isDate($0.date, inSameDayAs: today)
        }), let recipe = try await recipes.recipe(by: meal.recipeID) else { return nil }
        return TonightDinner(
            recipeID: recipe.id,
            title: recipe.title,
            minutes: recipe.prepMinutes + recipe.cookMinutes,
            photoFileName: recipe.photoFileName
        )
    }

    private func covers(_ plan: MealPlan, _ day: Date) -> Bool {
        let start = calendar.startOfDay(for: plan.startDate)
        guard let end = calendar.date(byAdding: .day, value: plan.days, to: start) else { return false }
        return day >= start && day < end
    }

    private func put(_ option: ScoredRecipe, on day: Date, in plan: MealPlan) async throws {
        let meals = try await plans.meals(for: plan.id)
        if var dinner = meals.first(where: { $0.slot == .dinner && calendar.isDate($0.date, inSameDayAs: day) }) {
            if dinner.recipeID != option.recipeID { dinner.swapHistory.append(dinner.recipeID) }
            dinner.recipeID = option.recipeID
            dinner.reasonCodes = option.reasonCodes
            dinner.leftoverOf = nil
            dinner.status = .planned
            try await plans.updateMeal(dinner)
        } else {
            let household = try await householdSize()
            try await plans.save(plan, meals: meals + [meal(option, on: day, planID: plan.id, servings: household)])
        }
    }

    /// The plan stretched so it runs through `day`, saved when it had to grow.
    private func lengthen(_ plan: MealPlan, toCover day: Date) async throws -> MealPlan {
        guard !covers(plan, day) else { return plan }
        let start = calendar.startOfDay(for: plan.startDate)
        let needed = (calendar.dateComponents([.day], from: start, to: day).day ?? 0) + 1
        var longer = plan
        longer.days = max(plan.days, needed)
        try await plans.save(longer, meals: try await plans.meals(for: plan.id))
        return longer
    }

    /// Archives a stale active plan and starts a plan from today through `day`, with `option` on that day.
    private func startPlan(from today: Date, through day: Date, with option: ScoredRecipe) async throws {
        guard let profile = try await profiles.profile() else { throw LarderError.notFound }
        let constraints = try await profiles.constraints()
        if var stale = try await plans.currentPlan() {
            let staleMeals = try await plans.meals(for: stale.id)
            stale.status = .archived
            try await plans.save(stale, meals: staleMeals)
        }
        let days = (calendar.dateComponents([.day], from: today, to: day).day ?? 0) + 1
        let plan = MealPlan(
            startDate: today,
            days: max(days, 1),
            constraintsSnapshot: service.compiled(profile: profile, constraints: constraints, targets: []).snapshot,
            solverVersion: Self.manualSolverVersion,
            seed: 0,
            status: .active
        )
        try await plans.save(plan, meals: [meal(option, on: day, planID: plan.id, servings: profile.householdSize)])
    }

    private func householdSize() async throws -> Int {
        guard let profile = try await profiles.profile() else { throw LarderError.notFound }
        return profile.householdSize
    }

    private func meal(_ option: ScoredRecipe, on day: Date, planID: MealPlanID, servings: Int) -> PlannedMeal {
        PlannedMeal(
            planID: planID,
            date: day,
            slot: .dinner,
            recipeID: option.recipeID,
            servings: max(servings, 1),
            status: .planned,
            reasonCodes: option.reasonCodes
        )
    }

    private func record(_ failure: any Error) {
        guard !(failure is CancellationError) else { return }
        error = failure as? LarderError ?? .storageFailure
    }
}
