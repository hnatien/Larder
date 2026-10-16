import Foundation
import Testing
@testable import LarderCore

struct PlanningMealSlotShareTests {
    @Test(arguments: [
        ([.dinner], 0.35),
        ([.breakfast, .dinner], 0.60),
        ([.lunch, .snack], 0.40),
        ([.breakfast, .lunch, .dinner], 0.90),
        ([], 0),
    ] as [(Set<MealType>, Double)])
    func coverageSumsPlannedSlots(slots: Set<MealType>, expected: Double) {
        #expect(Kitchen.isClose(MealSlotShare.coverage(slots: slots), expected))
    }

    @Test func fourSlotsCoverTheWholeDay() {
        #expect(MealSlotShare.coverage(slots: Set(MealType.allCases)) == 1)
        #expect(MealType.allCases.map(MealSlotShare.share(of:)) == [0.25, 0.30, 0.35, 0.10])
    }

    // MARK: Verifier

    /// One person, one day, one dinner of 700 kcal (35% of a 2,000 kcal day), 9 g fibre and 2,000 mg sodium.
    private func verifyDinner(targets: [NutrientTarget], slots: Set<MealType>) -> VerificationReport {
        let nutrition = RecipeNutrition(
            perServing: Nutrients(energyKcal: 700, fiberG: 9, sodiumMg: 2000),
            perRecipe: Nutrients(energyKcal: 1400, fiberG: 18, sodiumMg: 4000),
            coverage: 1, unresolved: []
        )
        let recipe = Kitchen.recipe("Fixed dinner", servings: 2)
        let candidate = RecipeCandidate(recipe: recipe, ingredients: [], nutrition: nutrition, foodGroupsGrams: [:])
        let dinner = PlannedMeal(planID: MealPlanID(), date: Planning.start, slot: .dinner, recipeID: recipe.id, servings: 1)
        return PlanVerifier.verify(
            meals: [dinner], candidates: [candidate], foods: [:], constraints: [], targets: targets, days: 1, householdSize: 1, slots: slots
        )
    }

    private static let energy = NutrientTarget(nutrient: .energy, basis: .perDay, min: 1800, max: 2200, priority: 3, source: .custom)

    @Test func dinnerOnlyCoverageReadsWithin() throws {
        let report = verifyDinner(targets: [Self.energy], slots: [.dinner])

        let note = try #require(report.nutrientNotes.first)
        #expect(note.status == .within)
        #expect(note.totalPerDay == 700)
        #expect(Kitchen.isClose(note.min, 630))
        #expect(Kitchen.isClose(note.max, 770))
        #expect(Kitchen.isClose(report.coverage, 0.35))
    }

    @Test func fullDayPlanComparesAgainstTheWholeDay() throws {
        let report = verifyDinner(targets: [Self.energy], slots: Set(MealType.allCases))

        let note = try #require(report.nutrientNotes.first)
        #expect(note == NutrientNote(nutrient: .energy, totalPerDay: 700, min: 1800, max: 2200, status: .under))
        #expect(Kitchen.isClose(report.coverage, 1))
    }

    @Test func dinnerCannotCarryADaysSodium() throws {
        let sodium = NutrientTarget(nutrient: .sodium, basis: .perDay, max: 2300, priority: 4, source: .custom)

        let dinnerOnly = try #require(verifyDinner(targets: [sodium], slots: [.dinner]).nutrientNotes.first)
        let wholeDay = try #require(verifyDinner(targets: [sodium], slots: Set(MealType.allCases)).nutrientNotes.first)

        #expect(dinnerOnly.status == .over)
        #expect(Kitchen.isClose(dinnerOnly.max, 805))
        #expect(dinnerOnly.min == nil)
        #expect(wholeDay.status == .within)
    }

    @Test func perThousandKcalAndPercentEnergyTargetsIgnoreCoverage() throws {
        let targets = [
            NutrientTarget(nutrient: .fiber, basis: .per1000kcal, target: 14, priority: 2, source: .dga2025),
            NutrientTarget(nutrient: .saturatedFat, basis: .percentEnergy, max: 10, priority: 2, source: .dga2025),
        ]

        let dinnerOnly = verifyDinner(targets: targets, slots: [.dinner])
        let wholeDay = verifyDinner(targets: targets, slots: Set(MealType.allCases))

        // 14 g per 1,000 kcal at 700 kcal is a 9.8 g floor either way
        let fibre = try #require(dinnerOnly.nutrientNotes.first)
        #expect(dinnerOnly.nutrientNotes.map(\.nutrient) == [.fiber])
        #expect(Kitchen.isClose(fibre.min, 9.8))
        #expect(fibre.status == .under)
        #expect(dinnerOnly.nutrientNotes == wholeDay.nutrientNotes)
    }

    @Test func noSlotsLeavePerDayTargetsUnchecked() {
        let report = verifyDinner(targets: [Self.energy], slots: [])

        #expect(report.nutrientNotes.isEmpty)
        #expect(report.coverage == 0)
    }

    // MARK: Planner

    @Test func plannerReportsTheCoverageOfItsSlots() {
        var request = Planning.request(days: 2)
        let dinners = WeekPlanner.plan(request)
        request.slots = [.breakfast, .dinner]
        let breakfastsAndDinners = WeekPlanner.plan(request)

        #expect(Kitchen.isClose(dinners.verification.coverage, 0.35))
        #expect(Kitchen.isClose(breakfastsAndDinners.verification.coverage, 0.60))
    }

    @Test func plannerObjectiveHoldsDinnersToTheirShare() throws {
        let lowest = try #require(Planning.candidates.compactMap(\.nutrition.perServing.energyKcal).min())
        // a floor no single dinner reaches as a whole day, yet every dinner clears as 35% of a day
        let floor = lowest / 0.35 * 0.99
        let target = NutrientTarget(nutrient: .energy, basis: .perDay, min: floor, priority: 3, source: .custom)

        let result = WeekPlanner.plan(Planning.request(targets: [target]))

        let note = try #require(result.verification.nutrientNotes.first { $0.nutrient == .energy })
        #expect(result.unfilledSlots.isEmpty)
        #expect(note.totalPerDay < floor)
        #expect(note.status == .within)
        #expect(result.breakdown.nutrientPenalty == 0)
    }
}
