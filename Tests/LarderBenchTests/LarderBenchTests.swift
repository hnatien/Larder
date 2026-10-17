import Foundation
import LarderCore
import LarderPersistence
import Testing
@testable import LarderBench

private enum Bench {
    static func catalogue() throws -> SeedCatalogue {
        try SeedCatalogue.load()
    }

    static func households(_ count: Int, seed: UInt64, catalogue: SeedCatalogue) -> [Household] {
        HouseholdGenerator.generate(
            count: count, seed: seed, catalogue: catalogue, start: Simulation.defaultStart, calendar: Simulation.gregorian
        )
    }

    static func meanPantryUse(_ runs: [HouseholdRun], arm: String) -> Double? {
        Metric.mean(runs.filter { $0.arm == arm }.compactMap(\.pantryUse))
    }
}

struct SeedCatalogueTests {
    @Test func decodesEverySeedFoodAndRecipe() throws {
        let catalogue = try Bench.catalogue()

        #expect(catalogue.foods.count == 113)
        #expect(catalogue.candidates.count == 42)
        #expect(catalogue.recipeIDsBySlug.count == 42)
        for lines in catalogue.ingredients.values {
            #expect(lines.allSatisfy { line in line.foodID.map { catalogue.foods[$0] != nil } ?? true })
        }
    }

    @Test func identifiersMatchTheAppSeedLoader() throws {
        let catalogue = try Bench.catalogue()

        #expect(catalogue.recipeIDsBySlug["weeknight-chana-masala"] == DeterministicID.recipeID(slug: "weeknight-chana-masala"))
        #expect(catalogue.foods[DeterministicID.foodID(slug: "onion")]?.name == "Onion, raw")
    }
}

struct SimulationSmokeTests {
    /// The fixed-seed smoke run: every arm stays inside the hard constraints, and the planner uses more of the
    /// pantry's perishables before they expire than random admitted recipes do.
    @Test func fixedSeedRunHasNoViolationsAndBeatsRandomOnPantryUse() async throws {
        let catalogue = try Bench.catalogue()
        let simulation = Simulation(catalogue: catalogue, seed: 7, weeks: 2)
        let runs = await LarderBench.evaluate(
            Bench.households(12, seed: 7, catalogue: catalogue),
            arms: [PlannerArm(), GreedyArm(), NoPantryArm(), RandomArm()],
            simulation: simulation
        )

        #expect(runs.count == 48)
        #expect(runs.allSatisfy { $0.weeks.count == 2 })
        #expect(runs.flatMap(\.weeks).allSatisfy { $0.hardViolations == 0 })
        let planner = try #require(Bench.meanPantryUse(runs, arm: "planner"))
        let random = try #require(Bench.meanPantryUse(runs, arm: "random"))
        #expect(planner > random)
    }

    @Test func sameSeedGivesTheSameHouseholdsAndPlans() throws {
        let catalogue = try Bench.catalogue()
        let first = Bench.households(3, seed: 11, catalogue: catalogue)
        let second = Bench.households(3, seed: 11, catalogue: catalogue)
        #expect(first.map(\.label) == second.map(\.label))
        #expect(first.map(\.pantry) == second.map(\.pantry))
        #expect(first.map(\.behaviour) == second.map(\.behaviour))

        let simulation = Simulation(catalogue: catalogue, seed: 11, weeks: 2)
        let recipes = { (run: HouseholdRun) in run.weeks.map { $0.plan.map(\.recipeID) } }
        let once = simulation.run(first[0], arm: PlannerArm())
        let again = simulation.run(second[0], arm: PlannerArm())
        #expect(recipes(once) == recipes(again))
        #expect(once.pantryUse == again.pantryUse)
        #expect(once.expiredGrams == again.expiredGrams)
    }

    @Test func householdsDrawEveryPersona() throws {
        let catalogue = try Bench.catalogue()
        let personas = Set(Bench.households(40, seed: 42, catalogue: catalogue).map(\.persona))

        #expect(personas == Set(Persona.allCases))
    }
}

struct FileArmTests {
    private func input(household: Household, catalogue: SeedCatalogue) -> WeekInput {
        let simulation = Simulation(catalogue: catalogue, seed: 1, weeks: 1)
        return WeekInput(
            household: household, week: 0, startDate: Simulation.defaultStart, days: 7, slots: [.dinner],
            candidates: catalogue.candidates, compiled: household.compiled,
            context: simulation.context(household: household, pantry: [], history: [], now: Simulation.defaultStart),
            seed: 1, planID: MealPlanID(), calendar: Simulation.gregorian
        )
    }

    @Test func readsPlansBySlugAndLinksLeftovers() throws {
        let catalogue = try Bench.catalogue()
        let household = Bench.households(1, seed: 3, catalogue: catalogue)[0]
        let file = FileArm.File(plans: [FileArm.Entry(household: 0, week: 0, meals: [
            FileArm.Meal(day: 0, slot: .dinner, recipe: "weeknight-chana-masala", servings: 4, leftoverOfDay: nil),
            FileArm.Meal(day: 1, slot: .dinner, recipe: "weeknight-chana-masala", servings: 2, leftoverOfDay: 0),
        ])])

        let plan = FileArm(file: file, catalogue: catalogue).plan(input(household: household, catalogue: catalogue))

        #expect(plan.meals.count == 2)
        #expect(plan.unfilledSlots == 5)
        #expect(plan.meals[0].recipeID == catalogue.recipeIDsBySlug["weeknight-chana-masala"])
        #expect(plan.meals[1].leftoverOf == plan.meals[0].id)
    }

    @Test func unknownRecipeIsAHardViolationAndMissingWeeksAreUnfilled() throws {
        let catalogue = try Bench.catalogue()
        let household = Bench.households(1, seed: 3, catalogue: catalogue)[0]
        let file = FileArm.File(plans: [FileArm.Entry(household: 0, week: 0, meals: [
            FileArm.Meal(day: 0, slot: .dinner, recipe: "invented-by-the-model", servings: nil, leftoverOfDay: nil),
        ])])
        let arm = FileArm(file: file, catalogue: catalogue)

        let run = Simulation(catalogue: catalogue, seed: 3, weeks: 2).run(household, arm: arm)

        #expect(run.weeks[0].hardViolations == 1)
        #expect(run.weeks[0].unfilledSlots == 6)
        #expect(run.weeks[1].plan.isEmpty)
        #expect(run.weeks[1].unfilledSlots == 7)
    }
}

struct PantryLedgerTests {
    private let now = Simulation.defaultStart

    private func food(_ name: String, _ group: FoodGroup) -> Food {
        Food(name: name, source: .seedApproximate, foodGroup: group)
    }

    @Test func consumesSoonestBestByFirstAndBooksExpiryAsWaste() {
        let spinach = food("spinach", .produce)
        let day = { (offset: Double) in self.now.addingTimeInterval(offset * 86_400) }
        var ledger = PantryLedger(items: [], foods: [spinach.id: spinach], idPrefix: "test")
        ledger.add(spinach, grams: 200, bestBy: day(5), on: now, source: .manual)
        ledger.add(spinach, grams: 100, bestBy: day(2), on: now, source: .manual)

        let shortfall = ledger.consume(spinach.id, grams: 150)
        ledger.expire(before: day(6))

        #expect(shortfall == 0)
        #expect(ledger.usedPerishable == 150)
        #expect(ledger.expiredPerishable == 150)
        #expect(ledger.items.isEmpty)
    }

    @Test func reportsShortfallAndIgnoresStaplesInPerishableShares() {
        let rice = food("rice", .grains)
        var ledger = PantryLedger(items: [], foods: [rice.id: rice], idPrefix: "test")
        ledger.add(rice, grams: 100, bestBy: now, on: now, source: .manual)

        #expect(ledger.consume(rice.id, grams: 250) == 150)
        #expect(ledger.usedPerishable == 0)
        #expect(ledger.expiredTotal == 0)
    }
}

struct ReportTests {
    @Test func summaryInterpolatesPercentiles() throws {
        let summary = try #require(Summary((1...10).map(Double.init)))

        #expect(summary.mean == 5.5)
        #expect(summary.median == 5.5)
        #expect(abs(summary.p90 - 9.1) < 1e-9)
        #expect(Summary([]) == nil)
    }

    @Test func cuisineEntropyIsInBits() {
        let record = { (cuisines: [String]) in
            WeekRecord(
                plan: [], unfilledSlots: 0, groceryLines: 0, hardViolations: 0, nutrientNotes: [], solveSeconds: 0,
                tonightMeals: 0, cuisines: cuisines
            )
        }

        #expect(record(["thai", "thai"]).cuisineEntropy == 0)
        #expect(record(["thai", "greek", "indian", "mexican"]).cuisineEntropy == 2)
        #expect(record([]).cuisineEntropy == nil)
    }

    @Test func rejectsBadFlags() {
        #expect(throws: LarderBench.UsageError.self) { try LarderBench.parse(["--households", "0"]) }
        #expect(throws: LarderBench.UsageError.self) { try LarderBench.parse(["--weeks"]) }
        #expect(throws: LarderBench.UsageError.self) { try LarderBench.parse(["--colour", "blue"]) }
        #expect((try? LarderBench.parse(["--seed", "9", "--households", "20", "--weeks", "2"]))?.households == 20)
    }
}
