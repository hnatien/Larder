import Foundation
import LarderCore
import Testing
@testable import FeatureLedger

@MainActor @Suite struct TonightModelTests {
    @Test func loadShowsThreeIdeasAndOtherIdeasPageThroughTheRest() async throws {
        let model = World().tonight()
        await model.load()
        #expect(model.options.count == 3)
        #expect(!model.shelvesAreEmpty)
        #expect(model.error == nil)
        #expect(model.pool.count <= TonightModel.poolLimit)
        let first = model.options.map(\.recipeID)
        #expect(Array(model.pool.prefix(3).map(\.recipeID)) == first)
        guard model.hasOtherIdeas else { return }
        model.showOtherIdeas()
        #expect(model.page == 1)
        #expect(Set(model.options.map(\.recipeID)).isDisjoint(with: first))
        let pages = (model.pool.count + 2) / 3
        #expect(model.dinner == nil)
        for _ in 1..<pages { model.showOtherIdeas() }
        #expect(model.page == 0)
        #expect(model.options.map(\.recipeID) == first)
    }

    @Test func otherIdeasWithNothingLoadedStaysOnTheFirstPage() {
        let model = World().tonight()
        model.showOtherIdeas()
        #expect(model.page == 0)
        #expect(model.options.isEmpty)
        #expect(model.dinner == nil)
    }

    @Test func loadFindsTonightsPlannedDinnerButNotASkippedOne() async throws {
        let world = World()
        let (_, meals) = await world.seed { plan in [Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0)] }
        let model = world.tonight()
        await model.load()
        #expect(model.dinner?.recipeID == Fixtures.lentilSoup.recipe.id)
        #expect(model.dinner?.title == Fixtures.lentilSoup.recipe.title)
        var skipped = meals[0]
        skipped.status = .skipped
        try await world.plans.updateMeal(skipped)
        await model.load()
        #expect(model.dinner == nil)
    }

    @Test func emptyShelvesAreReported() async {
        var world = World()
        world.pantry.stored = []
        let model = world.tonight()
        await model.load()
        #expect(model.shelvesAreEmpty)
    }

    @Test func expiringSpinachLeadsWithItsReason() async throws {
        let model = World().tonight()
        await model.load()
        let option = try #require(model.options.first { option in
            option.reasonCodes.contains { if case .usesExpiring = $0 { true } else { false } }
        })
        let expected = ReasonCopy.line(
            for: .usesExpiring(food: Fixtures.spinach.id, bestBy: Fixtures.pantry[0].bestBy ?? Fixtures.now),
            lookup: ReasonCopy.Lookup(foodNames: [Fixtures.spinach.id: Fixtures.spinach.name], calendar: Fixtures.calendar)
        )
        #expect(model.reasons(for: option).contains(expected))
        #expect(expected.hasPrefix("Uses the spinach before"))
        #expect(model.reasons(for: option, limit: 2).count <= 2)
    }

    @Test func cookTonightWithoutAPlanCreatesAOneDayPlan() async throws {
        let world = World()
        let model = world.tonight()
        await model.load()
        let option = try #require(model.options.first)
        await model.cookTonight(option)

        let plan = try #require(await world.plans.currentPlan())
        #expect(plan.days == 1)
        #expect(plan.startDate == Fixtures.today)
        #expect(plan.status == .active)
        #expect(plan.solverVersion == TonightModel.manualSolverVersion)
        let meals = await world.plans.meals(for: plan.id)
        #expect(meals.count == 1)
        #expect(meals[0].recipeID == option.recipeID)
        #expect(meals[0].slot == .dinner)
        #expect(meals[0].status == .planned)
        #expect(meals[0].date == Fixtures.today)
        #expect(meals[0].servings == 2)
        #expect(model.cookingID == option.recipeID)
        #expect(model.dinner?.title == option.candidate.recipe.title)
        #expect(!model.options.contains { $0.recipeID == option.recipeID }, "tonight's dinner is not offered again as an idea")
    }

    @Test func cookTonightReplacesTodaysDinnerInTheCurrentPlan() async throws {
        let world = World()
        let (plan, meals) = await world.seed { plan in
            [Fixtures.meal(Fixtures.beefRagu, in: plan, day: 0, status: .skipped), Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 1)]
        }
        let model = world.tonight()
        await model.load()
        let option = try #require(model.options.first { $0.recipeID != Fixtures.beefRagu.recipe.id })
        await model.cookTonight(option)

        #expect(await world.plans.storedPlans.count == 1)
        let stored = await world.plans.meals(for: plan.id)
        let dinner = try #require(stored.first { $0.id == meals[0].id })
        #expect(dinner.recipeID == option.recipeID)
        #expect(dinner.status == .planned)
        #expect(dinner.swapHistory == [Fixtures.beefRagu.recipe.id])
        #expect(stored.first { $0.id == meals[1].id } == meals[1])
    }

    @Test func cookTonightAddsADinnerWhenTodayIsEmpty() async throws {
        let world = World()
        let (plan, _) = await world.seed { plan in [Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 1)] }
        let model = world.tonight()
        await model.load()
        let option = try #require(model.options.first)
        await model.cookTonight(option)
        let stored = await world.plans.meals(for: plan.id)
        #expect(stored.count == 2)
        #expect(stored.contains { $0.date == Fixtures.today && $0.recipeID == option.recipeID })
    }

    @Test func cookTonightArchivesAStalePlan() async throws {
        let world = World()
        let (stale, _) = await world.seed(Fixtures.plan(start: Fixtures.day(-10))) { plan in
            [Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0, status: .cooked)]
        }
        let model = world.tonight()
        await model.load()
        let option = try #require(model.options.first)
        await model.cookTonight(option)
        #expect(await world.plans.plan(stale.id)?.status == .archived)
        #expect(await world.plans.meals(for: stale.id).count == 1)
        let current = try #require(await world.plans.currentPlan())
        #expect(current.id != stale.id)
        #expect(current.days == 1)
    }

    @Test func scheduleOnALaterDayLengthensTheCurrentPlan() async throws {
        let world = World()
        let (plan, _) = await world.seed(Fixtures.plan(start: Fixtures.today, days: 1)) { plan in
            [Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0)]
        }
        let model = world.tonight()
        await model.load()
        let option = try #require(model.options.first { $0.recipeID != Fixtures.lentilSoup.recipe.id })
        await model.schedule(option, on: Fixtures.day(3))

        let stored = try #require(await world.plans.plan(plan.id))
        #expect(stored.days == 4)
        let meals = await world.plans.meals(for: plan.id)
        #expect(meals.count == 2)
        #expect(meals.contains { $0.date == Fixtures.day(3) && $0.recipeID == option.recipeID && $0.slot == .dinner })
        #expect(model.dinner?.recipeID == Fixtures.lentilSoup.recipe.id)
    }

    @Test func scheduleWithoutAPlanRunsFromTodayToThatDay() async throws {
        let world = World()
        let model = world.tonight()
        await model.load()
        let option = try #require(model.options.first)
        await model.schedule(option, on: Fixtures.day(2))

        let plan = try #require(await world.plans.currentPlan())
        #expect(plan.startDate == Fixtures.today)
        #expect(plan.days == 3)
        let meals = await world.plans.meals(for: plan.id)
        #expect(meals.map(\.date) == [Fixtures.day(2)])
        #expect(model.dinner == nil)
    }

    @Test func scheduleInThePastLandsOnToday() async throws {
        let world = World()
        let model = world.tonight()
        await model.load()
        let option = try #require(model.options.first)
        await model.schedule(option, on: Fixtures.day(-2))
        let plan = try #require(await world.plans.currentPlan())
        #expect(await world.plans.meals(for: plan.id).map(\.date) == [Fixtures.today])
        #expect(model.dinner?.recipeID == option.recipeID)
    }

    @Test func cookTonightWithoutAProfileReportsNotFound() async throws {
        var world = World()
        let model = world.tonight()
        await model.load()
        let option = try #require(model.options.first)
        world.profiles.stored = nil
        let orphan = world.tonight()
        await orphan.cookTonight(option)
        #expect(orphan.error == .notFound)
        #expect(await world.plans.saveCount == 0)
    }

    @Test func loadWithoutAProfileReportsNotFound() async {
        var world = World()
        world.profiles.stored = nil
        let model = world.tonight()
        await model.load()
        #expect(model.options.isEmpty)
        #expect(model.error == .notFound)
        #expect(!model.isLoading)
    }
}
