import Foundation
import Testing
@testable import LarderCore

struct PlanningTasteTests {
    private func meal(
        _ candidate: RecipeCandidate,
        daysAgo: Double = 0,
        status: MealStatus,
        leftoverOf: PlannedMealID? = nil,
        swapHistory: [RecipeID] = []
    ) -> PlannedMeal {
        PlannedMeal(
            planID: MealPlanID(), date: Planning.day(-daysAgo), slot: .dinner, recipeID: candidate.recipe.id, servings: 2,
            leftoverOf: leftoverOf, status: status, swapHistory: swapHistory
        )
    }

    private func learn(_ history: [PlannedMeal]) -> TasteAffinity {
        TasteAffinity.learn(from: history, candidates: Planning.candidates, foods: Planning.foods, now: Planning.now)
    }

    @Test func noHistoryMeansNoSignal() {
        let taste = learn([])

        #expect(taste.values.isEmpty && taste.reasons.isEmpty)
        #expect(taste.affinity(for: Planning.chickenTikka.recipe.id) == 0)
    }

    @Test func cookedSkippedAndSwappedAwayWeighAsDocumented() {
        let taste = learn([
            meal(Planning.prawnStirFry, status: .cooked),
            meal(Planning.mushroomRisotto, status: .skipped),
            meal(Planning.mushroomRisotto, status: .skipped),
            meal(Planning.chickenTikka, status: .planned, swapHistory: [Planning.spinachOmelette.recipe.id]),
        ])

        #expect(Kitchen.isClose(taste.affinity(for: Planning.prawnStirFry.recipe.id), tanh(1)))
        #expect(Kitchen.isClose(taste.affinity(for: Planning.spinachOmelette.recipe.id), tanh(-0.4)))
        #expect(Kitchen.isClose(taste.affinity(for: Planning.mushroomRisotto.recipe.id), tanh(-1)))
        #expect(taste.affinity(for: Planning.chickenTikka.recipe.id) == 0)
    }

    @Test func evidenceHalvesEveryHalfLife() {
        let fresh = learn([meal(Planning.prawnStirFry, status: .cooked)])
        let old = learn([meal(Planning.prawnStirFry, daysAgo: TasteAffinity.halfLifeDays, status: .cooked)])

        #expect(Kitchen.isClose(old.affinity(for: Planning.prawnStirFry.recipe.id), tanh(0.5)))
        #expect(old.affinity(for: Planning.prawnStirFry.recipe.id) < fresh.affinity(for: Planning.prawnStirFry.recipe.id))
    }

    @Test func leftoversAddNothing() {
        let cooked = meal(Planning.prawnStirFry, status: .cooked)
        let leftover = meal(Planning.prawnStirFry, status: .cooked, leftoverOf: cooked.id)

        #expect(learn([cooked, leftover]) == learn([cooked]))
    }

    @Test func affinitySpreadsToTheSameCuisine() {
        let taste = learn([meal(Planning.chickenTikka, status: .cooked)])

        let curry = taste.affinity(for: Planning.chickpeaCurry.recipe.id)
        // the whole cuisine, plus half for tomatoes, one of the curry's two main ingredients
        #expect(Kitchen.isClose(curry, tanh(TasteAffinity.spread * 1.5)))
        #expect(curry < taste.affinity(for: Planning.chickenTikka.recipe.id))
        // prawns and broccoli share neither cuisine nor a main ingredient with the tikka
        #expect(taste.affinity(for: Planning.prawnStirFry.recipe.id) == 0)
    }

    @Test func affinitySpreadsThroughAMainIngredient() {
        let taste = learn([meal(Planning.beefRagu, status: .cooked)])

        #expect(TasteAffinity.mainIngredients(of: Planning.bulgogiBowl, foods: Planning.foods).first == Planning.beef.id)
        #expect(taste.affinity(for: Planning.bulgogiBowl.recipe.id) > 0)
    }

    @Test func dislikeSpreadsToo() {
        let taste = learn([meal(Planning.tofuBowl, status: .skipped), meal(Planning.tofuBowl, daysAgo: 1, status: .skipped)])

        #expect(taste.affinity(for: Planning.salmonTeriyaki.recipe.id) < 0)
    }

    @Test func mainIngredientsSkipStaplesAndGarnish() {
        let dish = Planning.dish(
            "Rice and spinach", cuisine: nil, servings: 2, prep: 5, cook: 5,
            [(Planning.rice, 500), (Planning.oliveOil, 100), (Planning.spinach, 80), (Planning.onion, 40), (Planning.tomato, 20)],
            garnish: [(Planning.mushroom, 300)]
        )

        #expect(TasteAffinity.mainIngredients(of: dish, foods: Planning.foods) == [Planning.spinach.id, Planning.onion.id])
    }

    @Test func cookingACuisineOftenGivesACuisineReason() {
        let taste = learn([meal(Planning.chickenTikka, status: .cooked), meal(Planning.chickpeaCurry, status: .cooked)])

        #expect(taste.reasons[Planning.chickpeaCurry.recipe.id] == .cooksOften(cuisine: "Indian"))
        #expect(taste.reasons[Planning.chickenTikka.recipe.id] == .cooksOften(cuisine: "Indian"))
    }

    @Test func cookingAnIngredientOftenGivesAnIngredientReason() {
        let taste = learn([meal(Planning.beefRagu, status: .cooked), meal(Planning.beefRagu, status: .cooked)])

        #expect(taste.reasons[Planning.bulgogiBowl.recipe.id] == .cooksOftenWith(food: Planning.beef.id))
    }

    @Test func noReasonWithoutEnoughCookingOrForADislikedRecipe() {
        let once = learn([meal(Planning.chickenTikka, status: .cooked)])
        let skippedButIndian = learn([
            meal(Planning.chickenTikka, status: .cooked),
            meal(Planning.chickpeaCurry, status: .cooked),
            meal(Planning.mushroomRisotto, status: .skipped),
        ])

        #expect(once.reasons.isEmpty)
        #expect(skippedButIndian.reasons[Planning.mushroomRisotto.recipe.id] == nil)
    }

    @Test func orderOfHistoryDoesNotMatter() {
        let history = [
            meal(Planning.chickenTikka, daysAgo: 3, status: .cooked),
            meal(Planning.beefRagu, daysAgo: 9, status: .cooked),
            meal(Planning.chickpeaCurry, daysAgo: 1, status: .skipped),
            meal(Planning.tofuBowl, daysAgo: 30, status: .cooked, swapHistory: [Planning.salmonTeriyaki.recipe.id]),
            meal(Planning.lentilSoup, daysAgo: 12, status: .cooked),
        ]

        #expect(learn(history) == learn(history.reversed()))
        #expect(learn(history) == learn([history[2], history[4], history[0], history[3], history[1]]))
    }

    @Test func learnedTasteReachesThePlanAndItsReasons() throws {
        let taste = learn([meal(Planning.chickenTikka, status: .cooked), meal(Planning.chickpeaCurry, status: .cooked)])
        var request = Planning.request(household: 2)
        request.context.taste = taste

        let result = WeekPlanner.plan(request)

        let curry = try #require(result.meals.first { $0.recipeID == Planning.chickpeaCurry.recipe.id && $0.leftoverOf == nil })
        #expect(curry.reasonCodes.contains(.cooksOften(cuisine: "Indian")))
    }
}
