import Foundation
import LarderCore
import Observation

/// Drives the Tonight tab: three pantry-first dinner ideas, offline and deterministic.
@Observable
@MainActor
public final class TonightModel {
    /// How many ideas Tonight shows.
    static let optionLimit = 3
    /// Written to `MealPlan.solverVersion` for a plan made from Tonight rather than the planner.
    static let manualSolverVersion = "manual"

    public private(set) var options: [ScoredRecipe] = []
    /// Whether the shelves hold nothing, so there is nothing to cook from.
    public private(set) var shelvesAreEmpty = false
    public private(set) var isLoading = false
    public private(set) var error: LarderError?
    /// The option "Pick for me" chose; one tap on "Cook this" commits it.
    public private(set) var pickedID: RecipeID?
    /// The option put on tonight's dinner.
    public private(set) var cookingID: RecipeID?
    private var foodsByID: [FoodID: Food] = [:]

    private let plans: any PlanRepository
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
        self.foods = foods
        self.pantry = pantry
        self.profiles = profiles
        self.dates = dates
        self.calendar = calendar
        self.service = PlanningService(
            plans: plans, recipes: recipes, foods: foods, pantry: pantry, profiles: profiles, dates: dates, calendar: calendar
        )
    }

    /// Loads up to three ideas, best first, and whether the shelves are empty.
    public func load() async {
        error = nil
        isLoading = true
        defer { isLoading = false }
        do {
            shelvesAreEmpty = try await pantry.items().isEmpty
            let found = try await service.tonight(limit: Self.optionLimit)
            let foodIDs = Set(found.flatMap(\.reasonCodes).compactMap { code -> FoodID? in
                if case .usesExpiring(let food, _) = code { food } else { nil }
            })
            let named = try await foods.foods(byIDs: Array(foodIDs))
            foodsByID = Dictionary(named.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            options = found
            if let pickedID, !found.contains(where: { $0.recipeID == pickedID }) { self.pickedID = nil }
        } catch {
            record(error)
        }
    }

    /// Chooses the top idea for someone who would rather not choose.
    @discardableResult
    public func pickForMe() -> ScoredRecipe? {
        let top = options.first
        pickedID = top?.recipeID
        return top
    }

    /// Puts `option` on today's dinner: in the active plan when it covers today, otherwise in a new one-day plan.
    public func cookTonight(_ option: ScoredRecipe) async {
        error = nil
        do {
            let today = calendar.startOfDay(for: dates.now)
            if let current = try await plans.currentPlan(), covers(current, today) {
                try await put(option, on: today, in: current)
            } else {
                try await startDay(today, with: option)
            }
            cookingID = option.recipeID
            pickedID = nil
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

    private func covers(_ plan: MealPlan, _ day: Date) -> Bool {
        let start = calendar.startOfDay(for: plan.startDate)
        guard let end = calendar.date(byAdding: .day, value: plan.days, to: start) else { return false }
        return day >= start && day < end
    }

    private func put(_ option: ScoredRecipe, on today: Date, in plan: MealPlan) async throws {
        let meals = try await plans.meals(for: plan.id)
        if var dinner = meals.first(where: { $0.slot == .dinner && calendar.isDate($0.date, inSameDayAs: today) }) {
            if dinner.recipeID != option.recipeID { dinner.swapHistory.append(dinner.recipeID) }
            dinner.recipeID = option.recipeID
            dinner.reasonCodes = option.reasonCodes
            dinner.leftoverOf = nil
            dinner.status = .planned
            try await plans.updateMeal(dinner)
        } else {
            let household = try await householdSize()
            try await plans.save(plan, meals: meals + [meal(option, on: today, planID: plan.id, servings: household)])
        }
    }

    /// Archives a stale active plan and starts a one-day plan for today.
    private func startDay(_ today: Date, with option: ScoredRecipe) async throws {
        guard let profile = try await profiles.profile() else { throw LarderError.notFound }
        let constraints = try await profiles.constraints()
        if var stale = try await plans.currentPlan() {
            let staleMeals = try await plans.meals(for: stale.id)
            stale.status = .archived
            try await plans.save(stale, meals: staleMeals)
        }
        let plan = MealPlan(
            startDate: today,
            days: 1,
            constraintsSnapshot: service.compiled(profile: profile, constraints: constraints, targets: []).snapshot,
            solverVersion: Self.manualSolverVersion,
            seed: 0,
            status: .active
        )
        try await plans.save(plan, meals: [meal(option, on: today, planID: plan.id, servings: profile.householdSize)])
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
