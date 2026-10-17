import Foundation
import Testing
@testable import LarderCore

/// Planner and verifier behaviour for nutrient targets, on recipes with fixed nutrition and no ingredient lines,
/// so a recipe's score is only its time fit plus novelty.
struct PlanningNutritionObjectiveTests {
    private func plate(_ title: String, minutes: Int, _ nutrients: Nutrients) -> RecipeCandidate {
        let recipe = Recipe(title: title, origin: .generated, servings: 1, prepMinutes: minutes, cookMinutes: 0)
        return RecipeCandidate(
            recipe: recipe, ingredients: [],
            nutrition: RecipeNutrition(perServing: nutrients, perRecipe: nutrients, coverage: 1, unresolved: []),
            foodGroupsGrams: [:]
        )
    }

    private func request(_ candidates: [RecipeCandidate], targets: [NutrientTarget], days: Int = 1, seed: UInt64 = 1) -> PlanRequest {
        Planning.request(candidates: candidates, household: 1, targets: targets, days: days, seed: seed, pantry: [])
    }

    private func score(_ candidate: RecipeCandidate) -> Double {
        RecipeScorer.score(candidate, context: Planning.context(pantry: [])).score
    }

    private static let fibre = NutrientTarget(nutrient: .fiber, basis: .per1000kcal, target: 14, priority: 2, source: .dga2025)

    // MARK: Bands

    @Test func percentEnergyBecomesGramsOfThePlansOwnEnergy() throws {
        let rich = plate("Rich", minutes: 10, Nutrients(energyKcal: 2000, saturatedFatG: 30, addedSugarG: 40))
        let targets = [
            NutrientTarget(nutrient: .saturatedFat, basis: .percentEnergy, max: 10, priority: 2, source: .dga2025),
            NutrientTarget(nutrient: .addedSugar, basis: .percentEnergy, max: 10, priority: 2, source: .who),
        ]
        let meal = PlannedMeal(planID: MealPlanID(), date: Planning.start, slot: .dinner, recipeID: rich.recipe.id, servings: 1)

        let report = PlanVerifier.verify(
            meals: [meal], candidates: [rich], foods: [:], constraints: [], targets: targets, days: 1, householdSize: 1, slots: [.dinner]
        )

        // 10 % of 2,000 kcal is 200 kcal: 22.2 g of fat at 9 kcal/g, 50 g of sugar at 4 kcal/g
        #expect(report.nutrientNotes.count == 2)
        let fat = try #require(report.nutrientNotes.first)
        let sugar = try #require(report.nutrientNotes.last)
        #expect(Kitchen.isClose(fat.max, 200.0 / 9))
        #expect(fat.status == .over)
        #expect(Kitchen.isClose(sugar.max, 50))
        #expect(sugar.status == .within)
    }

    @Test func percentEnergyOnANutrientWithoutEnergyHasNoBand() {
        let totals = PlanNutrition(meals: [], candidates: [:])
        let sodium = NutrientTarget(nutrient: .sodium, basis: .percentEnergy, max: 10, priority: 1, source: .custom)

        #expect(totals.dailyBand(for: sodium, days: 1, householdSize: 1, coverage: 1) == nil)
    }

    @Test func targetOnlyValueIsAFloor() throws {
        let totals = PlanNutrition(meals: [], candidates: [:])
        let potassium = NutrientTarget(nutrient: .potassium, basis: .perDay, target: 3000, priority: 1, source: .dga2025)

        let band = try #require(totals.dailyBand(for: potassium, days: 1, householdSize: 1, coverage: 0.35))

        #expect(Kitchen.isClose(band.min, 1050))
        #expect(band.max == nil)
    }

    // MARK: Objective

    @Test(arguments: Array(UInt64(1)...10))
    func picksTheHigherFibreRecipeWhenScoresAreClose(seed: UInt64) {
        // 14 g per 1,000 kcal at 600 kcal is an 8.4 g floor
        let lowFibre = plate("Quick white pasta", minutes: 10, Nutrients(energyKcal: 600, fiberG: 6))
        let highFibre = plate("Bean stew", minutes: 15, Nutrients(energyKcal: 600, fiberG: 8))
        #expect(score(lowFibre) > score(highFibre))
        #expect(score(lowFibre) - score(highFibre) < WeekPlanner.greedyBand)

        let result = WeekPlanner.plan(request([lowFibre, highFibre], targets: [Self.fibre], seed: seed))

        #expect(result.meals.map(\.recipeID) == [highFibre.recipe.id])
        #expect(result.breakdown.nutrientPenalty > 0)
    }

    @Test(arguments: Array(UInt64(1)...5))
    func saturatedFatOverItsShareOfEnergyIsAvoided(seed: UInt64) {
        let fatty = plate("Cream pie", minutes: 10, Nutrients(energyKcal: 700, saturatedFatG: 14))
        let lean = plate("Grilled fish", minutes: 15, Nutrients(energyKcal: 700, saturatedFatG: 5))
        let target = NutrientTarget(nutrient: .saturatedFat, basis: .percentEnergy, max: 10, priority: 2, source: .dga2025)

        let result = WeekPlanner.plan(request([fatty, lean], targets: [target], seed: seed))

        #expect(result.meals.map(\.recipeID) == [lean.recipe.id])
        #expect(result.breakdown.nutrientPenalty == 0)
    }

    @Test(arguments: Array(UInt64(1)...5))
    func potassiumTargetPullsLikeAFloor(seed: UInt64) {
        let low = plate("Plain rice", minutes: 10, Nutrients(energyKcal: 700, potassiumMg: 700))
        let high = plate("Potato and greens", minutes: 15, Nutrients(energyKcal: 700, potassiumMg: 1100))
        let target = NutrientTarget(nutrient: .potassium, basis: .perDay, target: 3000, priority: 1, source: .dga2025)

        let result = WeekPlanner.plan(request([low, high], targets: [target], seed: seed))

        #expect(result.meals.map(\.recipeID) == [high.recipe.id])
    }

    @Test(arguments: Array(UInt64(1)...5))
    func hypertensionSodiumCapShapesAMaintainPlan(seed: UInt64) {
        let profile = Planning.profile(household: 1)
        let targets = NutrientTargets.defaults(
            for: profile, constraints: [Kitchen.constraint(.medical(.hypertension))], referenceYear: 2026
        ).filter { $0.nutrient == .sodium }
        // 2,000 mg a day is 700 mg for a dinner; 2,300 mg would be 805 mg
        let salty = plate("Ramen", minutes: 10, Nutrients(energyKcal: 700, sodiumMg: 790))
        let lighter = plate("Noodle salad", minutes: 15, Nutrients(energyKcal: 700, sodiumMg: 650))

        let result = WeekPlanner.plan(request([salty, lighter], targets: targets, seed: seed))

        #expect(profile.goal == .maintain)
        #expect(result.meals.map(\.recipeID) == [lighter.recipe.id])
    }

    // MARK: Search

    @Test(arguments: Array(UInt64(1)...10))
    func searchReachesALowScoringRecipeThatClosesTheGap(seed: UInt64) {
        // Six quick low-fibre plates outrank the stew by more than the greedy band, so neither the greedy fill nor
        // the top-scoring alternatives ever reach it; only the gap-targeted alternatives do.
        let quick = (5...10).map { minutes in plate("Quick plate \(minutes)", minutes: minutes, Nutrients(energyKcal: 600, fiberG: 2)) }
        let stew = plate("Bean stew", minutes: 25, Nutrients(energyKcal: 600, fiberG: 9))
        #expect(score(quick[0]) - score(stew) > WeekPlanner.greedyBand)

        let result = WeekPlanner.plan(request(quick + [stew], targets: [Self.fibre], seed: seed))

        #expect(result.meals.map(\.recipeID) == [stew.recipe.id])
        #expect(result.breakdown.nutrientPenalty == 0)
    }
}
