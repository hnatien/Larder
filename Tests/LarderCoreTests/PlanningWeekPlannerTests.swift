import Foundation
import Testing
@testable import LarderCore

/// What two plans are compared on; meal and plan identifiers are random by design.
private func signature(_ result: PlanResult) -> [String] {
    result.meals.map { meal in
        "\(meal.date.timeIntervalSince1970)|\(meal.slot)|\(meal.recipeID.rawValue)|\(meal.servings)|\(meal.leftoverOf != nil)"
    }
}

struct PlanningWeekPlannerTests {
    @Test func sameSeedProducesIdenticalMeals() {
        let first = WeekPlanner.plan(Planning.request(seed: 99))
        let second = WeekPlanner.plan(Planning.request(seed: 99))

        #expect(signature(first) == signature(second))
        #expect(first.meals.filter { $0.leftoverOf == nil }.map(\.reasonCodes) == second.meals.filter { $0.leftoverOf == nil }.map(\.reasonCodes))
        #expect(first.breakdown == second.breakdown)
    }

    @Test func differentSeedsDifferInAtLeastOneMeal() {
        let first = WeekPlanner.plan(Planning.request(seed: 1))
        let second = WeekPlanner.plan(Planning.request(seed: 2))

        #expect(first.meals.count == 7)
        #expect(signature(first) != signature(second))
    }

    @Test(arguments: Array(UInt64(1)...10))
    func neverPlansARecipeTwiceExceptAsLeftovers(seed: UInt64) {
        let result = WeekPlanner.plan(Planning.request(seed: seed))
        let cooked = result.meals.filter { $0.leftoverOf == nil }.map(\.recipeID)

        #expect(Set(cooked).count == cooked.count)
        #expect(result.meals.count + result.unfilledSlots.count == 7)
    }

    @Test func leftoverFollowsABatchRecipeAndLinksBack() throws {
        let request = Planning.request(
            candidates: [Planning.chickpeaCurry, Planning.bulgogiBowl], household: 4, days: 2,
            liked: [Planning.chickpeaCurry.recipe.id]
        )

        let result = WeekPlanner.plan(request)

        #expect(result.meals.count == 2)
        let cooked = try #require(result.meals.first)
        let leftover = try #require(result.meals.last)
        #expect(cooked.recipeID == Planning.chickpeaCurry.recipe.id)
        #expect(cooked.servings == 8)
        #expect(cooked.leftoverOf == nil)
        #expect(leftover.recipeID == cooked.recipeID)
        #expect(leftover.leftoverOf == cooked.id)
        #expect(leftover.servings == 4)
        #expect(leftover.reasonCodes == [.leftoverOf(meal: cooked.id)])
        #expect(leftover.date == Planning.calendar.date(byAdding: .day, value: 1, to: cooked.date))
        #expect(result.unfilledSlots.isEmpty)
    }

    @Test(arguments: Array(UInt64(1)...10))
    func everyLeftoverIsLinkedToTheMealTheDayBefore(seed: UInt64) {
        let result = WeekPlanner.plan(Planning.request(household: 4, seed: seed))
        let byID = Dictionary(uniqueKeysWithValues: result.meals.map { ($0.id, $0) })

        for leftover in result.meals where leftover.leftoverOf != nil {
            let source = leftover.leftoverOf.flatMap { byID[$0] }
            #expect(source?.recipeID == leftover.recipeID)
            #expect(source?.servings == 8)
            #expect(leftover.servings == 4)
            #expect(source.flatMap { Planning.calendar.date(byAdding: .day, value: 1, to: $0.date) } == leftover.date)
        }
        let batchCooked = result.meals.filter { meal in
            meal.leftoverOf == nil && (Planning.recipe(meal.recipeID)?.recipe.servings ?? 0) >= 8 && meal.date < Fixtures.date(2026, 10, 25)
        }
        #expect(batchCooked.allSatisfy { meal in result.meals.contains { $0.leftoverOf == meal.id } })
    }

    @Test func smallRecipesGetNoLeftover() {
        let result = WeekPlanner.plan(Planning.request(candidates: [Planning.bulgogiBowl, Planning.tofuBowl], household: 2, days: 2))

        #expect(result.meals.allSatisfy { $0.leftoverOf == nil && $0.servings == 2 })
        #expect(result.meals.count == 2)
    }

    @Test func cuisineQuotaHoldsWhenOneCuisineScoresBest() {
        let italian = (1...6).map { index in
            Planning.dish("Italian dish \(index)", cuisine: "Italian", servings: 2, prep: 5, cook: 5, [(Planning.rice, 200), (Planning.tomato, 100)])
        }
        let others = [Planning.bulgogiBowl, Planning.tofuBowl, Planning.prawnStirFry, Planning.chickenTikka]

        let result = WeekPlanner.plan(Planning.request(
            candidates: italian + others, household: 2, liked: Set(italian.map(\.recipe.id))
        ))
        let italianIDs = Set(italian.map(\.recipe.id))
        let italianCount = result.meals.filter { italianIDs.contains($0.recipeID) }.count

        #expect(result.meals.count == 7)
        #expect(italianCount == 3)
        #expect(result.breakdown.varietyPenalty == 0)
    }

    @Test func quotaBreachIsPenalisedRatherThanLeavingSlotsEmpty() {
        let italian = (1...4).map { index in
            Planning.dish("Italian dish \(index)", cuisine: "Italian", servings: 2, prep: 5, cook: 5, [(Planning.rice, 200)])
        }

        let result = WeekPlanner.plan(Planning.request(candidates: italian, household: 2, days: 4))

        #expect(result.meals.count == 4)
        // quota for 4 days is 2, so two Italian dinners are over it
        #expect(result.breakdown.varietyPenalty == 2 * WeekPlanner.quotaPenalty)
    }

    @Test func lockedMealIsKeptExactlyAsGiven() throws {
        let probe = Planning.request()
        let locked = PlannedMeal(
            planID: probe.planID, date: Fixtures.date(2026, 10, 21), slot: .dinner,
            recipeID: Planning.beefRagu.recipe.id, servings: 3, isLocked: true, reasonCodes: [.underBudget]
        )

        let result = WeekPlanner.plan(Planning.request(lockedMeals: [locked]))

        #expect(result.meals.contains(locked))
        #expect(result.meals.filter { $0.recipeID == Planning.beefRagu.recipe.id } == [locked])
        #expect(result.meals.filter { $0.date == locked.date }.count == 1)
    }

    @Test func lockedMealOutsideThePlanIsIgnored() {
        let locked = PlannedMeal(
            planID: MealPlanID(), date: Fixtures.date(2026, 11, 30), slot: .dinner,
            recipeID: Planning.beefRagu.recipe.id, servings: 2, isLocked: true
        )

        let result = WeekPlanner.plan(Planning.request(lockedMeals: [locked]))

        #expect(!result.meals.contains(locked))
    }

    @Test func lockedViolatingMealStaysAndIsReported() throws {
        let locked = PlannedMeal(
            planID: MealPlanID(), date: Planning.start, slot: .dinner,
            recipeID: Planning.romescoChicken.recipe.id, servings: 4, isLocked: true
        )

        let result = WeekPlanner.plan(Planning.request(Persona.nutAllergy.constraints, lockedMeals: [locked]))

        #expect(result.meals.contains(locked))
        let violation = try #require(result.verification.hardViolations.first)
        #expect(result.verification.hardViolations.count == 1)
        #expect(violation.plannedMealID == locked.id)
        #expect(violation.reasons.contains("Contains tree nuts (almond)"))
    }

    @Test(arguments: [15, 30])
    func timeCapIsRespected(cap: Int) {
        let result = WeekPlanner.plan(Planning.request(maxCookMinutes: cap))

        #expect(!result.meals.isEmpty)
        #expect(result.meals.allSatisfy { (Planning.recipe($0.recipeID)?.totalMinutes ?? .max) <= cap })
    }

    @Test func equipmentIsRespected() {
        let result = WeekPlanner.plan(Planning.request(equipment: [.stovetop]))

        #expect(result.meals.count == 7)
        #expect(result.meals.allSatisfy { Planning.recipe($0.recipeID)?.recipe.tags.equipment.isSubset(of: [.stovetop]) == true })
    }

    @Test(arguments: Persona.allCases, Array(UInt64(1)...50))
    func fiftySeedsZeroHardViolations(persona: Persona, seed: UInt64) {
        let result = WeekPlanner.plan(Planning.request(persona.constraints, seed: seed))

        #expect(result.verification.hardViolations.isEmpty)
        #expect(result.unfilledSlots.isEmpty)
        for meal in result.meals {
            let candidate = Planning.recipe(meal.recipeID)
            let verdict = candidate.map {
                ConstraintFilter().verdict(recipe: $0.recipe, ingredients: $0.ingredients, foods: Planning.foods, constraints: persona.constraints)
            }
            #expect(verdict == .pass(softPenalties: []), "\(candidate?.recipe.title ?? "missing") planned for \(persona)")
        }
        if persona == .nutAllergy {
            #expect(!result.meals.contains { $0.recipeID == Planning.romescoChicken.recipe.id })
        }
    }

    @Test(arguments: Array(UInt64(1)...20))
    func unlabelledTahiniRecipeIsNeverPlanned(seed: UInt64) {
        let result = WeekPlanner.plan(Planning.request(
            Persona.nutAllergy.constraints, seed: seed, liked: [Planning.falafelBowl.recipe.id]
        ))

        #expect(!result.meals.contains { $0.recipeID == Planning.falafelBowl.recipe.id })
    }

    @Test func infeasiblePersonaReturnsUnfilledSlots() {
        let result = WeekPlanner.plan(Planning.request(Persona.vegan.constraints, maxCookMinutes: 10))

        #expect(result.meals.isEmpty)
        #expect(result.unfilledSlots.map(\.date) == (19...25).map { Fixtures.date(2026, 10, $0) })
        #expect(result.unfilledSlots.allSatisfy { $0.slot == .dinner })
        #expect(result.verification.hardViolations.isEmpty)
        #expect(result.breakdown.mealScoreTotal == 0)
    }

    @Test func zeroDaysOrNoSlotsPlanNothing() {
        var noSlots = Planning.request()
        noSlots.slots = []

        let zeroDays = WeekPlanner.plan(Planning.request(days: 0))
        let empty = WeekPlanner.plan(noSlots)

        #expect(zeroDays.meals.isEmpty && zeroDays.unfilledSlots.isEmpty && zeroDays.plan.days == 0)
        #expect(empty.meals.isEmpty && empty.unfilledSlots.isEmpty)
    }

    @Test func multipleSlotsFillEachMealTypeFromFittingRecipes() {
        let porridge = Planning.dish("Porridge", cuisine: "Scottish", servings: 1, prep: 2, cook: 5, mealTypes: [.breakfast], [(Planning.rice, 80)])
        var request = Planning.request(candidates: Planning.candidates + [porridge], household: 1, days: 2)
        request.slots = [.breakfast, .dinner]

        let result = WeekPlanner.plan(request)
        let breakfasts = result.meals.filter { $0.slot == .breakfast }

        #expect(breakfasts.count == 1)
        #expect(breakfasts.first?.recipeID == porridge.recipe.id)
        #expect(result.unfilledSlots.count == 1)
        #expect(result.meals.filter { $0.slot == .dinner }.count == 2)
    }

    @Test func planCarriesMetadata() {
        let request = Planning.request(Persona.coeliac.constraints, seed: 12345)

        let result = WeekPlanner.plan(request)

        #expect(result.plan.id == request.planID)
        #expect(result.plan.startDate == Planning.start)
        #expect(result.plan.days == 7)
        #expect(result.plan.seed == 12345)
        #expect(result.plan.solverVersion == "1.0")
        #expect(result.plan.status == .draft)
        #expect(result.plan.constraintsSnapshot == request.compiled.snapshot)
        #expect(result.meals.allSatisfy { $0.planID == request.planID && !$0.isLocked && $0.status == .planned })
        let breakdown = result.breakdown
        #expect(Kitchen.isClose(breakdown.objective, breakdown.mealScoreTotal - breakdown.nutrientPenalty - breakdown.varietyPenalty))
    }

    @Test func freshMealsCarryTheirScorerReasons() throws {
        let result = WeekPlanner.plan(Planning.request(Persona.nutAllergy.constraints))
        let meal = try #require(result.meals.first { $0.leftoverOf == nil })
        let candidate = try #require(Planning.recipe(meal.recipeID))
        let scorerCodes = RecipeScorer.score(candidate, context: Planning.context()).reasonCodes

        #expect(Array(meal.reasonCodes.prefix(scorerCodes.count)) == scorerCodes)
    }

    @Test func sevenDayPlanIsFast() {
        let request = Planning.request(Persona.nutAllergy.constraints)
        let clock = ContinuousClock()

        let elapsed = clock.measure { _ = WeekPlanner.plan(request) }

        #expect(elapsed < .milliseconds(500))
    }

    @Test func verifierBackstopsAFaultyAdmission() {
        let request = Planning.request(
            Persona.nutAllergy.constraints,
            liked: [Planning.romescoChicken.recipe.id, Planning.falafelBowl.recipe.id]
        )

        let result = WeekPlanner.plan(request) { _ in .admitted(softPenalties: []) }
        let planned = Set(result.meals.map(\.recipeID))

        #expect(result.verification.hardViolations.isEmpty)
        #expect(!planned.contains(Planning.romescoChicken.recipe.id))
        #expect(!planned.contains(Planning.falafelBowl.recipe.id))
        #expect(result.unfilledSlots.isEmpty)
    }

    @Test func slotsThatKeepFailingVerificationEndUnfilled() {
        let nutty = (1...6).map { index in
            Planning.dish("Almond dish \(index)", cuisine: "Cuisine \(index)", servings: 2, prep: 5, cook: 5, [(Planning.almonds, 50), (Planning.rice, 100)])
        }

        let result = WeekPlanner.plan(Planning.request(Persona.nutAllergy.constraints, candidates: nutty, household: 2, days: 3)) { _ in
            .admitted(softPenalties: [])
        }

        #expect(result.meals.isEmpty)
        #expect(result.unfilledSlots.count == 3)
        #expect(result.verification.hardViolations.isEmpty)
    }
}

struct PlanningVerifierTests {
    private func meal(_ candidate: RecipeCandidate, servings: Int = 2, day: Int = 0, leftoverOf: PlannedMealID? = nil) -> PlannedMeal {
        PlannedMeal(
            planID: MealPlanID(), date: Planning.start.addingTimeInterval(Double(day) * 86_400), slot: .dinner,
            recipeID: candidate.recipe.id, servings: servings, leftoverOf: leftoverOf
        )
    }

    private func verify(_ meals: [PlannedMeal], constraints: [DietaryConstraint], targets: [NutrientTarget] = [], days: Int = 7, household: Int = 2) -> VerificationReport {
        PlanVerifier.verify(
            meals: meals, candidates: Planning.candidates, foods: Planning.foods, constraints: constraints,
            targets: targets, days: days, householdSize: household
        )
    }

    @Test func catchesAnInjectedAllergenMeal() throws {
        var result = WeekPlanner.plan(Planning.request(Persona.nutAllergy.constraints))
        let injected = meal(Planning.romescoChicken, day: 3)
        result.meals[2] = injected

        let report = verify(result.meals, constraints: Persona.nutAllergy.constraints)

        let violation = try #require(report.hardViolations.first)
        #expect(report.hardViolations.count == 1)
        #expect(violation.plannedMealID == injected.id)
        #expect(violation.recipeID == Planning.romescoChicken.recipe.id)
        #expect(violation.reasons.contains("Contains tree nuts (almond)"))
    }

    @Test func uncertainMealIsAHardViolation() throws {
        let falafel = meal(Planning.falafelBowl)

        let report = verify([falafel, meal(Planning.chickenTikka, day: 1)], constraints: Persona.coeliac.constraints)

        let violation = try #require(report.hardViolations.first)
        #expect(report.hardViolations.count == 1)
        #expect(violation.plannedMealID == falafel.id)
        #expect(violation.reasons.contains("No gluten data (tahini)"))
    }

    @Test func mealWithoutRecipeDataIsAHardViolation() {
        let unknown = PlannedMeal(planID: MealPlanID(), date: Planning.start, slot: .dinner, recipeID: RecipeID(), servings: 2)

        let report = verify([unknown], constraints: [])

        #expect(report.hardViolations == [Violation(plannedMealID: unknown.id, recipeID: unknown.recipeID, reasons: ["No recipe data, so it cannot be checked"])])
    }

    @Test func cleanPlanHasNoViolations() {
        let report = verify([meal(Planning.chickenTikka), meal(Planning.tofuBowl, day: 1)], constraints: Persona.nutAllergy.constraints)

        #expect(report.hardViolations.isEmpty)
    }

    @Test func nutrientNotesReadUnderWithinAndOver() throws {
        let nutrition = RecipeNutrition(
            perServing: Nutrients(energyKcal: 500, proteinG: 20, fiberG: 5, sodiumMg: 600),
            perRecipe: Nutrients(energyKcal: 1000, proteinG: 40, fiberG: 10, sodiumMg: 1200),
            coverage: 1, unresolved: []
        )
        let recipe = Kitchen.recipe("Fixed plate", servings: 2)
        let candidate = RecipeCandidate(recipe: recipe, ingredients: [], nutrition: nutrition, foodGroupsGrams: [.grains: 100])
        let plated = PlannedMeal(planID: MealPlanID(), date: Planning.start, slot: .dinner, recipeID: recipe.id, servings: 2)
        let targets = [
            NutrientTarget(nutrient: .energy, basis: .perDay, min: 900, max: 1100, priority: 3, source: .custom),
            NutrientTarget(nutrient: .protein, basis: .perDay, min: 50, max: 100, priority: 3, source: .custom),
            NutrientTarget(nutrient: .sodium, basis: .perDay, max: 1000, priority: 4, source: .custom),
            NutrientTarget(nutrient: .fiber, basis: .per1000kcal, target: 14, priority: 2, source: .dga2025),
            NutrientTarget(nutrient: .saturatedFat, basis: .percentEnergy, max: 10, priority: 2, source: .dga2025),
            NutrientTarget(nutrient: .potassium, basis: .perDay, target: 3000, priority: 1, source: .dga2025),
        ]

        let report = PlanVerifier.verify(
            meals: [plated], candidates: [candidate], foods: [:], constraints: [], targets: targets, days: 1, householdSize: 1
        )

        #expect(report.nutrientNotes.map(\.nutrient) == [.energy, .protein, .sodium, .fiber])
        #expect(report.nutrientNotes[0] == NutrientNote(nutrient: .energy, totalPerDay: 1000, min: 900, max: 1100, status: .within))
        #expect(report.nutrientNotes[1] == NutrientNote(nutrient: .protein, totalPerDay: 40, min: 50, max: 100, status: .under))
        #expect(report.nutrientNotes[2] == NutrientNote(nutrient: .sodium, totalPerDay: 1200, min: nil, max: 1000, status: .over))
        // 14 g per 1,000 kcal at 1,000 kcal a day is a 14 g floor
        #expect(report.nutrientNotes[3] == NutrientNote(nutrient: .fiber, totalPerDay: 10, min: 14, max: nil, status: .under))
        #expect(report.shelfBalance.levels[.grains] == .comfortable)
    }

    @Test func leftoversAreNotCountedTwiceAndSkippedMealsNotAtAll() throws {
        let cooked = meal(Planning.chickpeaCurry, servings: 8)
        let leftover = meal(Planning.chickpeaCurry, servings: 4, day: 1, leftoverOf: cooked.id)
        var skipped = meal(Planning.tofuBowl, servings: 4, day: 2)
        skipped.status = .skipped
        let target = NutrientTarget(nutrient: .energy, basis: .perDay, min: 1, priority: 3, source: .custom)

        let report = verify([cooked, leftover, skipped], constraints: [], targets: [target], days: 2, household: 4)

        let perServing = try #require(Planning.chickpeaCurry.nutrition.perServing.energyKcal)
        let note = try #require(report.nutrientNotes.first)
        #expect(Kitchen.isClose(note.totalPerDay, perServing * 8 / 2 / 4, tolerance: 1e-6))
    }

    @Test func fibreGapLandsOnTheHighestFibreMeal() throws {
        let target = NutrientTarget(nutrient: .fiber, basis: .perDay, min: 60, priority: 2, source: .custom)
        let request = Planning.request(Persona.nutAllergy.constraints, household: 2, targets: [target])

        let result = WeekPlanner.plan(request)

        let tagged = result.meals.filter { meal in meal.reasonCodes.contains { if case .fibreGap = $0 { true } else { false } } }
        let gapMeal = try #require(tagged.first)
        #expect(tagged.count == 1)
        let fibre = { (meal: PlannedMeal) in (Planning.recipe(meal.recipeID)?.nutrition.perServing.fiberG ?? 0) * Double(meal.servings) }
        let richest = result.meals.filter { $0.leftoverOf == nil }.map(fibre).max() ?? 0
        #expect(fibre(gapMeal) == richest)
        let note = try #require(result.verification.nutrientNotes.first { $0.nutrient == .fiber })
        #expect(note.status == .under)
        // a dinner-only plan is held to a dinner's share of the 60 g day
        let floor = 60 * MealSlotShare.coverage(slots: [.dinner])
        #expect(Kitchen.isClose(note.min, floor))
        guard case .fibreGap(let short) = gapMeal.reasonCodes.last else {
            Issue.record("fibreGap should be the last reason")
            return
        }
        #expect(Kitchen.isClose(short, (floor - note.totalPerDay) * 7, tolerance: 1e-6))
        #expect(short > 0)
    }

    @Test func noFibreGapWhenFibreIsMet() {
        let target = NutrientTarget(nutrient: .fiber, basis: .perDay, min: 1, priority: 2, source: .custom)

        let result = WeekPlanner.plan(Planning.request(targets: [target]))

        #expect(!result.meals.contains { $0.reasonCodes.contains { if case .fibreGap = $0 { true } else { false } } })
    }
}
