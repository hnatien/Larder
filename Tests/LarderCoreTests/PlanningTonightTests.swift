import Foundation
import Testing
@testable import LarderCore

struct PlanningTonightTests {
    private func admission(_ compiled: CompiledConstraints) -> (RecipeCandidate) -> Admission {
        { compiled.admits($0, foods: Planning.foods) }
    }

    @Test func returnsThreeOptionsByDefaultAndHonoursTheLimit() {
        let compiled = Planning.compiled()

        let three = TonightPicker.pick(candidates: Planning.candidates, admission: admission(compiled), context: Planning.context())
        let two = TonightPicker.pick(candidates: Planning.candidates, admission: admission(compiled), context: Planning.context(), limit: 2)
        let none = TonightPicker.pick(candidates: Planning.candidates, admission: admission(compiled), context: Planning.context(), limit: 0)

        #expect(three.count == 3)
        #expect(two.map(\.recipeID) == Array(three.prefix(2)).map(\.recipeID))
        #expect(none.isEmpty)
    }

    @Test func neverRepeatsACuisineOrARecipe() {
        let doubled = Planning.candidates + Planning.candidates

        let picks = TonightPicker.pick(
            candidates: doubled, admission: admission(Planning.compiled()), context: Planning.context(), limit: 20
        )
        let cuisines = picks.compactMap { $0.candidate.recipe.tags.cuisine }

        #expect(Set(picks.map(\.recipeID)).count == picks.count)
        #expect(Set(cuisines).count == cuisines.count)
        #expect(picks.count == 11)
    }

    @Test func prefersADifferentPrimaryProtein() {
        let context = Planning.context(liked: [Planning.chickenTikka.recipe.id, Planning.romescoChicken.recipe.id])
        let pool = [Planning.chickenTikka, Planning.romescoChicken, Planning.bulgogiBowl]
        let ranked = pool.map { RecipeScorer.score($0, context: context) }.sorted { $0.score > $1.score }

        let picks = TonightPicker.pick(candidates: pool, admission: admission(Planning.compiled()), context: context)

        #expect(ranked[2].recipeID == Planning.bulgogiBowl.recipe.id)
        #expect(picks.count == 3)
        #expect(picks[1].recipeID == Planning.bulgogiBowl.recipe.id)
        #expect(TonightPicker.primaryProtein(of: Planning.romescoChicken, foods: Planning.foods) == .poultry)
        #expect(TonightPicker.primaryProtein(of: Planning.tofuBowl, foods: Planning.foods) == nil)
    }

    @Test func returnsFewerWhenCuisinesRunOut() {
        let picks = TonightPicker.pick(
            candidates: [Planning.beefRagu, Planning.mushroomRisotto],
            admission: admission(Planning.compiled()),
            context: Planning.context()
        )

        #expect(picks.count == 1)
    }

    @Test func skipsUncertainExcludedAndNonDinnerRecipes() {
        let breakfast = Planning.dish("Porridge", cuisine: "Scottish", servings: 1, prep: 2, cook: 5, mealTypes: [.breakfast], [(Planning.rice, 80)])
        let pool = [Planning.falafelBowl, Planning.romescoChicken, breakfast, Planning.tofuBowl]

        let picks = TonightPicker.pick(
            candidates: pool, admission: admission(Planning.compiled(Persona.nutAllergy.constraints)), context: Planning.context()
        )

        #expect(picks.map(\.recipeID) == [Planning.tofuBowl.recipe.id])
    }
}

struct PlanningSwapTests {
    private let compiled = Planning.compiled(Persona.nutAllergy.constraints)

    private var result: PlanResult {
        WeekPlanner.plan(Planning.request(Persona.nutAllergy.constraints))
    }

    @Test func excludesRecipesAlreadyInThePlan() throws {
        let result = result
        let meal = try #require(result.meals.first { $0.leftoverOf == nil })

        let suggestions = SwapSuggester.suggest(
            for: meal, in: result, candidates: Planning.candidates,
            admission: { compiled.admits($0, foods: Planning.foods) }, context: Planning.context()
        )
        let planned = Set(result.meals.map(\.recipeID))

        #expect(!suggestions.isEmpty)
        #expect(suggestions.allSatisfy { !planned.contains($0.recipeID) })
        #expect(suggestions.count <= 5)
    }

    @Test func respectsAdmission() throws {
        let result = result
        let meal = try #require(result.meals.first)

        let suggestions = SwapSuggester.suggest(
            for: meal, in: result, candidates: Planning.candidates,
            admission: { compiled.admits($0, foods: Planning.foods) }, context: Planning.context(), limit: 20
        )
        let ids = Set(suggestions.map(\.recipeID))

        #expect(!ids.contains(Planning.romescoChicken.recipe.id))
        #expect(!ids.contains(Planning.falafelBowl.recipe.id))
        #expect(suggestions.allSatisfy { compiled.admits($0.candidate, foods: Planning.foods) == .admitted(softPenalties: []) })
        #expect(SwapSuggester.suggest(
            for: meal, in: result, candidates: Planning.candidates, admission: { _ in .excluded(reasons: []) }, context: Planning.context()
        ).isEmpty)
    }

    @Test func sharingShoppingWithThePlanEarnsABonus() {
        let planID = MealPlanID()
        let kept = PlannedMeal(planID: planID, date: Planning.start, slot: .dinner, recipeID: Planning.salmonTraybake.recipe.id, servings: 2)
        let swapped = PlannedMeal(
            planID: planID, date: Planning.start.addingTimeInterval(86_400), slot: .dinner, recipeID: Planning.tofuBowl.recipe.id, servings: 2
        )
        let report = VerificationReport(hardViolations: [], nutrientNotes: [], shelfBalance: ShelfBalance(levels: [:]))
        let result = PlanResult(
            plan: MealPlan(id: planID, startDate: Planning.start, days: 2, constraintsSnapshot: "", solverVersion: "1.0", seed: 1, status: .draft),
            meals: [kept, swapped],
            unfilledSlots: [],
            breakdown: PlanScoreBreakdown(mealScoreTotal: 0, nutrientPenalty: 0, varietyPenalty: 0, objective: 0),
            verification: report
        )
        // shares broccoli and sweet potato with the traybake's shopping; the omelette shares nothing
        let sharing = Planning.dish("Roast veg", cuisine: "British", servings: 2, prep: 10, cook: 20, [(Planning.broccoli, 200), (Planning.sweetPotato, 200)])
        let plain = Planning.dish("Mushroom omelette", cuisine: "French", servings: 2, prep: 5, cook: 20, [(Planning.mushroom, 200), (Planning.eggs, 100)])
        let context = Planning.context()
        let plainScore = RecipeScorer.score(plain, context: context).score
        let sharingScore = RecipeScorer.score(sharing, context: context).score

        let suggestions = SwapSuggester.suggest(
            for: swapped, in: result, candidates: [plain, sharing, Planning.salmonTraybake],
            admission: { _ in .admitted(softPenalties: []) }, context: context
        )

        #expect(plainScore > sharingScore)
        #expect(plainScore - sharingScore < SwapSuggester.sharedFoodsBonus)
        #expect(suggestions.map(\.recipeID) == [sharing.recipe.id, plain.recipe.id])
        #expect(Kitchen.isClose(suggestions[0].score, sharingScore + SwapSuggester.sharedFoodsBonus))
        #expect(Kitchen.isClose(suggestions[1].score, plainScore))
    }
}
