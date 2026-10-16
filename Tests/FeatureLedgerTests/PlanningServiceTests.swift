import Foundation
import LarderCore
import Testing
@testable import FeatureLedger

@Suite struct PlanningServiceTests {
    let world = World()

    @Test func candidatesBuildOnePerRecipeWithNutrition() async throws {
        let candidates = try await world.service().candidates()
        #expect(candidates.count == Fixtures.recipes.count)
        #expect(Set(candidates.map(\.recipe.id)) == Set(Fixtures.recipes.map(\.id)))
        let curry = try #require(candidates.first { $0.recipe.id == Fixtures.chickpeaCurry.recipe.id })
        #expect(curry.ingredients.count == Fixtures.chickpeaCurry.lines.count)
        #expect((curry.nutrition.perServing.energyKcal ?? 0) > 0)
        #expect((curry.foodGroupsGrams[.legumes] ?? 0) == 800)
    }

    @Test func catalogueForSomeRecipesSkipsUnknownIdentifiers() async throws {
        let catalogue = try await world.service().catalogue(for: [Fixtures.lentilSoup.recipe.id, RecipeID()])
        #expect(catalogue.candidates.map(\.recipe.id) == [Fixtures.lentilSoup.recipe.id])
        #expect(catalogue.foods[Fixtures.lentils.id] != nil)
        #expect(catalogue.foods[Fixtures.beef.id] == nil)
    }

    @Test func contextCountsRecencyOnlyWithinTwentyEightDays() async throws {
        let service = world.service()
        let catalogue = try await service.catalogue()
        let plan = Fixtures.plan(start: Fixtures.day(-40), days: 60)
        let meals = [
            Fixtures.meal(Fixtures.beefRagu, in: plan, day: 30),
            Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 5),
            Fixtures.meal(Fixtures.beanTacos, in: plan, day: 45),
        ]
        let context = service.context(for: Fixtures.profile(), pantry: Fixtures.pantry, recentPlans: meals, catalogue: catalogue)
        #expect(context.recentlyPlanned[Fixtures.beefRagu.recipe.id] == meals[0].date)
        #expect(context.recentlyPlanned[Fixtures.lentilSoup.recipe.id] == nil)
        #expect(context.recentlyPlanned[Fixtures.beanTacos.recipe.id] == nil)
        #expect(context.now == Fixtures.now)
        #expect(context.goal == .lessWaste)
        #expect(context.maxCookMinutes == 60)
    }

    @Test func contextCountsCuisinesOnlyWithinSevenDays() async throws {
        let service = world.service()
        let catalogue = try await service.catalogue()
        let plan = Fixtures.plan(start: Fixtures.day(-20), days: 21)
        let meals = [
            Fixtures.meal(Fixtures.beanTacos, in: plan, day: 17),
            Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 8),
        ]
        let context = service.context(for: Fixtures.profile(), pantry: [], recentPlans: meals, catalogue: catalogue)
        #expect(context.recentCuisines["mexican"] == meals[0].date)
        #expect(context.recentCuisines["moroccan"] == nil)
    }

    @Test func cookedMeansLikedAndOnlyTwoSkipsMeanSkipped() async throws {
        let service = world.service()
        let catalogue = try await service.catalogue()
        let plan = Fixtures.plan(start: Fixtures.day(-7))
        let meals = [
            Fixtures.meal(Fixtures.chickenTikka, in: plan, day: 0, status: .cooked),
            Fixtures.meal(Fixtures.beefRagu, in: plan, day: 1, status: .skipped),
            Fixtures.meal(Fixtures.tofuBowl, in: plan, day: 2, status: .skipped),
            Fixtures.meal(Fixtures.tofuBowl, in: plan, day: 4, status: .skipped),
        ]
        let context = service.context(for: Fixtures.profile(), pantry: [], recentPlans: meals, catalogue: catalogue)
        #expect(context.liked == [Fixtures.chickenTikka.recipe.id])
        #expect(context.skipped == [Fixtures.tofuBowl.recipe.id])
    }

    @Test func compiledFollowsTheProfile() {
        let compiled = world.service().compiled(profile: Fixtures.profile(household: 3, maxCookMinutes: 25), constraints: [], targets: [])
        #expect(compiled.maxCookMinutes == 25)
        #expect(compiled.householdSize == 3)
        #expect(compiled.targets.isEmpty)
    }

    @Test func tonightGivesAtMostThreeAdmittedDinnersFromDifferentCuisines() async throws {
        let options = try await world.service().tonight(limit: 3)
        #expect(options.count == 3)
        let cuisines = options.compactMap { $0.candidate.recipe.tags.cuisine?.lowercased() }
        #expect(Set(cuisines).count == options.count)
        #expect(try await world.service().tonight(limit: 0).isEmpty)
    }

    @Test func planWeekFillsSevenDays() async throws {
        let result = try await world.service().planWeek(startDate: Fixtures.today, seed: 7, locked: [])
        #expect(result.plan.days == PlanningService.weekDays)
        #expect(result.meals.count == 7)
        #expect(result.unfilledSlots.isEmpty)
        #expect(result.meals.allSatisfy { $0.planID == result.plan.id && $0.slot == .dinner })
        #expect(result.verification.hardViolations.isEmpty)
    }

    @Test func planWeekWithoutAProfileThrowsNotFound() async {
        var world = World()
        world.profiles.stored = nil
        await #expect(throws: LarderError.notFound) {
            _ = try await world.service().planWeek(startDate: Fixtures.today, seed: 1, locked: [])
        }
    }
}
