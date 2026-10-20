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

    static func metric(_ key: String) throws -> Metric {
        try #require(Metric.all.first { $0.key == key })
    }

    static func week(_ plan: [PlannedMeal] = [], hardViolations: Int = 0) -> WeekRecord {
        WeekRecord(
            plan: plan, unfilledSlots: 0, groceryLines: 0, hardViolations: hardViolations, nutrientNotes: [],
            solveSeconds: 0, tonightMeals: 0, cuisines: []
        )
    }

    static func meal(_ slug: String, status: MealStatus = .cooked, leftoverOf: PlannedMealID? = nil) -> PlannedMeal {
        PlannedMeal(
            planID: MealPlanID(), date: Simulation.defaultStart, slot: .dinner,
            recipeID: RecipeID(rawValue: SeedCatalogue.uuid(for: slug)), servings: 2, leftoverOf: leftoverOf, status: status
        )
    }

    /// A one-week run with the given waste per week and starting-pantry use, for statistics and gate tests.
    static func run(
        _ household: Household, arm: String = "planner", seed: UInt64 = 1, waste: Double = 0, startingUse: Double? = nil,
        weeks: [WeekRecord] = [week()]
    ) -> HouseholdRun {
        HouseholdRun(
            household: household, arm: arm, seed: seed, weeks: weeks, pantryUse: nil, startingPantryUse: startingUse,
            expiredGrams: waste * Double(weeks.count), expiredPerishableGrams: 0
        )
    }
}

struct SeedCatalogueTests {
    @Test func decodesEverySeedFoodAndRecipe() throws {
        let catalogue = try Bench.catalogue()

        #expect(catalogue.foods.count == 113)
        #expect(catalogue.candidates.count == 191)
        #expect(catalogue.recipeIDsBySlug.count == 191)
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
        // Cuisines count only planned dinners cooked from scratch, never skipped ones or leftovers.
        for week in runs.flatMap(\.weeks) {
            #expect(week.cuisines.count == Metric.cooked(week.plan).count)
        }
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
        #expect(run.weeks[1].nutrientNotes.isEmpty)
    }

    @Test func nutrientsAreAveragedOverFilledDinnersOnly() throws {
        let catalogue = try Bench.catalogue()
        let household = Bench.households(1, seed: 3, catalogue: catalogue)[0]
        let slug = "weeknight-chana-masala"
        let file = FileArm.File(plans: [FileArm.Entry(household: 0, week: 0, meals: [
            FileArm.Meal(day: 0, slot: .dinner, recipe: slug, servings: nil, leftoverOfDay: nil),
        ])])
        let recipe = try #require(catalogue.recipeIDsBySlug[slug])
        let perServing = try #require(catalogue.candidates.first { $0.recipe.id == recipe }?.nutrition.perServing.energyKcal)

        let run = Simulation(catalogue: catalogue, seed: 3, weeks: 1).run(household, arm: FileArm(file: file, catalogue: catalogue))

        // One dinner for the household and six empty slots: the energy per filled dinner is one serving's, not a seventh of it.
        let energy = try #require(run.weeks[0].nutrientNotes.first { $0.nutrient == .energy })
        #expect(abs(energy.totalPerDay - perServing) < 1e-9)
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
        #expect(throws: LarderBench.UsageError.self) { try LarderBench.parse(["--seeds", "0"]) }
        #expect(throws: LarderBench.UsageError.self) { try LarderBench.parse(["--seeds", "2", "--llm-plans", "plans.json"]) }
        #expect((try? LarderBench.parse(["--seed", "9", "--seeds", "3"]))?.seedList == [9, 10, 11])
        #expect((try? LarderBench.parse(["--seed", "\(UInt64.max)", "--seeds", "2"]))?.seedList == [UInt64.max, 0])
    }

    @Test func repeatMetricsCountOnlyDinnersCookedFromScratch() throws {
        let household = Bench.households(1, seed: 3, catalogue: try Bench.catalogue())[0]
        let dal = Bench.meal("dal")
        let first = Bench.week([dal, Bench.meal("dal", leftoverOf: dal.id), Bench.meal("soup", status: .skipped)])
        // The skipped soup last week and the skipped dal this week are neither repeats nor history.
        let second = Bench.week([Bench.meal("soup"), Bench.meal("dal", status: .skipped), Bench.meal("stew")])
        let run = Bench.run(household, weeks: [first, second])

        #expect(try Bench.metric("repeat_within_week").value(run) == 0)
        #expect(try Bench.metric("repeat_across_weeks").value(run) == 0)
        #expect(Metric.cooked(first.plan).map(\.id) == [dal.id])
    }
}

struct BootstrapTests {
    @Test func noValuesHaveNoInterval() {
        #expect(Bootstrap.mean([]) == nil)
        #expect(Bootstrap.mean([[], []]) == nil)
        #expect(Bootstrap.mean([[1, 2]], resamples: 0) == nil)
    }

    @Test func oneValueOrConstantValuesGiveAZeroWidthInterval() {
        #expect(Bootstrap.mean([[3.5]]) == Interval(mean: 3.5, low: 3.5, high: 3.5, count: 1))
        #expect(Bootstrap.mean([[], [2, 2, 2], [2]]) == Interval(mean: 2, low: 2, high: 2, count: 4))
    }

    @Test func intervalCoversTheMeanAtTheNormalWidth() throws {
        // 100 values of 0 and 1: standard error 0.05, so the 95% interval is close to 0.5 ± 0.098.
        let values = (0..<100).map { Double($0 % 2) }
        let interval = try #require(Bootstrap.mean([values]))

        #expect(interval.mean == 0.5)
        #expect(interval.count == 100)
        #expect(abs(interval.low - 0.402) < 0.02)
        #expect(abs(interval.high - 0.598) < 0.02)
        #expect(Bootstrap.mean([values]) == interval)
    }

    @Test func seedsArePooledAndResampledSeparately() throws {
        // Every resample keeps one value from each seed, so the pooled mean can only move by half a seed's spread.
        let interval = try #require(Bootstrap.mean([[0], [10]]))

        #expect(interval == Interval(mean: 5, low: 5, high: 5, count: 2))
    }

    @Test func differencesPairHouseholdsWithinEachSeed() throws {
        let households = Bench.households(3, seed: 3, catalogue: try Bench.catalogue())
        let waste = try Bench.metric("waste_g_per_week")
        let starting = try Bench.metric("starting_pantry_use")
        let runs = [
            Bench.run(households[0], seed: 2, waste: 100, startingUse: 0.5),
            Bench.run(households[1], seed: 2, waste: 300, startingUse: nil),
            Bench.run(households[2], seed: 2, waste: 500),
            Bench.run(households[0], arm: "greedy", seed: 2, waste: 150, startingUse: 0.25),
            Bench.run(households[1], arm: "greedy", seed: 2, waste: 200, startingUse: 0.5),
            // The same household index under another seed is a different household.
            Bench.run(households[0], seed: 1, waste: 10),
            Bench.run(households[0], arm: "greedy", seed: 1, waste: 40),
        ]

        // Household 2 has no greedy run and household 1 no planner value, so neither pairs.
        #expect(Bootstrap.differences(runs, arm: "planner", baseline: "greedy", metric: waste) == [[-30], [-50, 100]])
        #expect(Bootstrap.differences(runs, arm: "planner", baseline: "greedy", metric: starting) == [[], [0.25]])
        #expect(Bootstrap.differences(runs, arm: "planner", baseline: "random", metric: waste) == [[], []])
        #expect(Bootstrap.values(runs, arm: "planner", metric: waste) == [[10], [100, 300, 500]])
    }
}

struct BaselineTests {
    private let configuration = Baseline.Configuration(seed: 42, seeds: 1, households: 2, weeks: 1)

    private func runs(waste: [Double], startingUse: Double? = 0.4, violations: Int = 0) throws -> [HouseholdRun] {
        let households = Bench.households(waste.count, seed: 3, catalogue: try Bench.catalogue())
        return zip(households, waste).map { household, waste in
            Bench.run(household, waste: waste, startingUse: startingUse, weeks: [Bench.week(hardViolations: violations)])
        }
    }

    @Test func passesOnTheRunItWasWrittenFromAndOnImprovements() throws {
        let baseline = Baseline(runs: try runs(waste: [1000, 2000]), configuration: configuration)

        #expect(try baseline.failures(try runs(waste: [1000, 2000]), configuration: configuration).isEmpty)
        #expect(try baseline.failures(try runs(waste: [500, 600], startingUse: 0.9), configuration: configuration).isEmpty)
        #expect(try baseline.markdown(try runs(waste: [1000, 2000]), configuration: configuration).contains("FAIL") == false)
    }

    @Test func toleratesChangesInsideTheBaselineIntervalOnly() throws {
        let baseline = Baseline(runs: try runs(waste: [1000, 2000]), configuration: configuration)
        let waste = try #require(baseline.metrics["waste_g_per_week"])
        #expect(waste.mean == 1500)
        #expect(waste.high == 2000)

        // A mean of 1,900 g is worse but inside the interval; 2,100 g is past its upper bound.
        #expect(try baseline.failures(try runs(waste: [1800, 2000]), configuration: configuration).isEmpty)
        let failures = try baseline.failures(try runs(waste: [2000, 2200]), configuration: configuration)
        #expect(failures.count == 1)
        #expect(failures.first?.hasPrefix("Grams expired per week") == true)
    }

    @Test func higherIsBetterMetricsFailBelowTheLowerBound() throws {
        let baseline = Baseline(runs: try runs(waste: [1000, 1000], startingUse: 0.4), configuration: configuration)

        let failures = try baseline.failures(try runs(waste: [1000, 1000], startingUse: 0.39), configuration: configuration)
        #expect(failures.count == 1)
        #expect(failures.first?.hasPrefix("Starting-pantry perishables") == true)
    }

    @Test func oneHouseholdBaselineFailsOnAnyWorsening() throws {
        let one = Baseline.Configuration(seed: 42, seeds: 1, households: 1, weeks: 1)
        let baseline = Baseline(runs: try runs(waste: [1000]), configuration: one)

        #expect(baseline.metrics["waste_g_per_week"] == Interval(mean: 1000, low: 1000, high: 1000, count: 1))
        #expect(try baseline.failures(try runs(waste: [1000]), configuration: one).isEmpty)
        #expect(try baseline.failures(try runs(waste: [1000.5]), configuration: one).count == 1)
    }

    @Test func anyHardViolationFails() throws {
        let baseline = Baseline(runs: try runs(waste: [1000, 2000]), configuration: configuration)

        let failures = try baseline.failures(try runs(waste: [1000, 2000], violations: 1), configuration: configuration)
        #expect(failures == ["planner has 2 hard-constraint violations (must be 0)"])
    }

    @Test func aMetricThatLosesOrGainsItsValuesFails() throws {
        let measured = Baseline(runs: try runs(waste: [1000, 2000], startingUse: 0.4), configuration: configuration)
        let unmeasured = Baseline(runs: try runs(waste: [1000, 2000], startingUse: nil), configuration: configuration)
        #expect(unmeasured.metrics["starting_pantry_use"] == nil)
        // No week-over-week pairs in a one-week run: both sides lack the metric, which is not a regression.
        #expect(measured.metrics["repeat_across_weeks"] == nil)

        #expect(try measured.failures(try runs(waste: [1000, 2000], startingUse: nil), configuration: configuration).count == 1)
        #expect(try unmeasured.failures(try runs(waste: [1000, 2000], startingUse: 0.4), configuration: configuration).count == 1)
        #expect(try measured.failures([], configuration: configuration).count == 2)
    }

    @Test func refusesARunWithOtherFlags() throws {
        let baseline = Baseline(runs: try runs(waste: [1000, 2000]), configuration: configuration)
        var other = configuration
        other.weeks = 4

        #expect(throws: Baseline.Failure.self) { try baseline.failures(try runs(waste: [1000, 2000]), configuration: other) }
    }

    @Test func roundTripsThroughJSON() throws {
        let baseline = Baseline(runs: try runs(waste: [1000, 2000]), configuration: configuration)
        let url = FileManager.default.temporaryDirectory.appending(path: "larder-bench-baseline-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try baseline.write(to: url)

        #expect(try Baseline.load(from: url) == baseline)
    }
}
