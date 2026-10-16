import Foundation
import LarderCore
import Testing
@testable import LarderPersistence

struct PlanRepositoryTests {
    let plans: GRDBPlanRepository

    init() throws {
        plans = GRDBPlanRepository(database: try LarderDatabase.inMemory())
    }

    @Test func planAndMealsRoundTripEveryField() async throws {
        let plan = MealPlan(
            startDate: Fixtures.date(2026, 10, 19),
            days: 7,
            constraintsSnapshot: "sha256:abc",
            solverVersion: "planner-1.2",
            seed: UInt64.max,
            status: .active
        )
        let first = Fixtures.meal(planID: plan.id, date: Fixtures.date(2026, 10, 19), slot: .dinner)
        let leftover = PlannedMeal(
            planID: plan.id,
            date: Fixtures.date(2026, 10, 20),
            slot: .lunch,
            recipeID: first.recipeID,
            servings: 1,
            leftoverOf: first.id,
            isLocked: true,
            status: .cooked,
            reasonCodes: Fixtures.allReasonCodes,
            swapHistory: [RecipeID(), RecipeID()]
        )
        try await plans.save(plan, meals: [first, leftover])
        #expect(try await plans.plans() == [plan])
        #expect(try await plans.meals(for: plan.id) == [first, leftover])
    }

    @Test func saveReplacesMeals() async throws {
        let plan = Fixtures.plan(start: Fixtures.date(2026, 10, 19), status: .active)
        try await plans.save(plan, meals: [
            Fixtures.meal(planID: plan.id, date: Fixtures.date(2026, 10, 19), slot: .dinner),
            Fixtures.meal(planID: plan.id, date: Fixtures.date(2026, 10, 20), slot: .dinner),
        ])
        var updated = plan
        updated.days = 3
        let replacement = [Fixtures.meal(planID: plan.id, date: Fixtures.date(2026, 10, 21), slot: .lunch)]
        try await plans.save(updated, meals: replacement)
        #expect(try await plans.plans() == [updated])
        #expect(try await plans.meals(for: plan.id) == replacement)
    }

    @Test func currentPlanIsTheActivePlanWithTheLatestStart() async throws {
        let older = Fixtures.plan(start: Fixtures.date(2026, 10, 12), status: .active)
        let latest = Fixtures.plan(start: Fixtures.date(2026, 10, 19), status: .active)
        let draft = Fixtures.plan(start: Fixtures.date(2026, 10, 26), status: .draft)
        let archived = Fixtures.plan(start: Fixtures.date(2026, 11, 2), status: .archived)
        for plan in [older, latest, draft, archived] {
            try await plans.save(plan, meals: [])
        }
        #expect(try await plans.currentPlan() == latest)
        #expect(try await plans.plans() == [archived, draft, latest, older])
    }

    @Test func currentPlanIsNilWithoutAnActivePlan() async throws {
        #expect(try await plans.currentPlan() == nil)
        try await plans.save(Fixtures.plan(start: Fixtures.date(2026, 10, 19), status: .draft), meals: [])
        #expect(try await plans.currentPlan() == nil)
    }

    @Test func mealsAreOrderedByDateThenSlot() async throws {
        let plan = Fixtures.plan(start: Fixtures.date(2026, 10, 19), status: .active)
        let monday = Fixtures.date(2026, 10, 19)
        let tuesday = Fixtures.date(2026, 10, 20)
        let meals = [
            Fixtures.meal(planID: plan.id, date: tuesday, slot: .breakfast),
            Fixtures.meal(planID: plan.id, date: monday, slot: .snack),
            Fixtures.meal(planID: plan.id, date: monday, slot: .dinner),
            Fixtures.meal(planID: plan.id, date: monday, slot: .breakfast),
            Fixtures.meal(planID: plan.id, date: monday, slot: .lunch),
        ]
        try await plans.save(plan, meals: meals)
        let ordered = try await plans.meals(for: plan.id)
        #expect(ordered.map(\.slot) == [.breakfast, .lunch, .dinner, .snack, .breakfast])
        #expect(ordered.last?.date == tuesday)
    }

    @Test func updateMealReplacesOneMeal() async throws {
        let plan = Fixtures.plan(start: Fixtures.date(2026, 10, 19), status: .active)
        var meal = Fixtures.meal(planID: plan.id, date: Fixtures.date(2026, 10, 19), slot: .dinner)
        let other = Fixtures.meal(planID: plan.id, date: Fixtures.date(2026, 10, 20), slot: .dinner)
        try await plans.save(plan, meals: [meal, other])
        meal.status = .skipped
        meal.swapHistory = [meal.recipeID]
        meal.recipeID = RecipeID()
        try await plans.updateMeal(meal)
        #expect(try await plans.meals(for: plan.id) == [meal, other])
    }

    @Test func updatingAMissingMealThrowsNotFound() async throws {
        let plan = Fixtures.plan(start: Fixtures.date(2026, 10, 19), status: .active)
        try await plans.save(plan, meals: [])
        let missing = Fixtures.meal(planID: plan.id, date: Fixtures.date(2026, 10, 19), slot: .dinner)
        await #expect {
            try await plans.updateMeal(missing)
        } throws: { error in
            guard case PersistenceError.notFound = error else { return false }
            return true
        }
    }
}
