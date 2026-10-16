import Foundation
import Testing
@testable import LarderCore

struct PlanningRandomTests {
    @Test func seededRandomMatchesSplitMix64ReferenceOutputs() {
        var random = SeededRandom(seed: 0)

        #expect(random.next() == 0xE220_A839_7B1D_CDAF)
        #expect(random.next() == 0x6E78_9E6A_A1B9_65F4)
        #expect(random.next() == 0x06C4_5D18_8009_454F)
    }

    @Test func sameSeedRepeatsTheSequence() {
        var first = SeededRandom(seed: 42)
        var second = SeededRandom(seed: 42)

        #expect((0..<100).map { _ in first.next() } == (0..<100).map { _ in second.next() })
    }

    @Test func neighbouringSeedsDiverge() {
        var first = SeededRandom(seed: 1)
        var second = SeededRandom(seed: 2)

        let shared = zip((0..<100).map { _ in first.next() }, (0..<100).map { _ in second.next() }).filter { $0 == $1 }
        #expect(shared.isEmpty)
    }

    @Test func boundedDrawsAreRoughlyUniform() {
        var random = SeededRandom(seed: 7)
        var buckets = [Int](repeating: 0, count: 10)
        for _ in 0..<10_000 {
            buckets[Int(random.next(upperBound: UInt64(10)))] += 1
        }
        let mean = (0..<10_000).reduce(0.0) { total, _ in total + Double.random(in: 0..<1, using: &random) } / 10_000

        #expect(buckets.allSatisfy { (900...1100).contains($0) })
        #expect(abs(mean - 0.5) < 0.02)
    }
}

struct PlanningCandidateTests {
    @Test func builderGroupsGramsByFoodGroupForTheWholeRecipe() {
        let tikka = Planning.chickenTikka

        #expect(tikka.foodGroupsGrams == [.protein: 600, .grains: 300, .produce: 550, .fats: 30])
        // energy: 600*1.77 + 300*1.30 + 400*0.18 + 150*0.40 + 30*8.84 = 1062 + 390 + 72 + 60 + 265.2
        #expect(Kitchen.isClose(tikka.nutrition.perRecipe.energyKcal, 1849.2))
        #expect(Kitchen.isClose(tikka.nutrition.perServing.energyKcal, 462.3))
        #expect(tikka.totalMinutes == 40)
    }

    @Test func builderSkipsGarnishAndUnresolvedLinesInFoodGroups() {
        let recipe = Kitchen.recipe("Rice with extras")
        let lines = [
            Kitchen.line("rice", 200, .gram, food: Planning.rice, recipe: recipe.id),
            Kitchen.line("spinach", 30, .gram, food: Planning.spinach, recipe: recipe.id, garnish: true),
            Kitchen.line("a splash of something", 1, .piece, recipe: recipe.id),
        ]

        let candidate = CandidateBuilder.build(recipes: [recipe], ingredients: [recipe.id: lines], foods: Planning.foods)[0]

        #expect(candidate.foodGroupsGrams == [.grains: 200])
        #expect(candidate.nutrition.unresolved == [lines[2].id])
    }

    @Test func recipeWithoutIngredientLinesBuildsAnEmptyCandidate() {
        let recipe = Kitchen.recipe("Bare")

        let candidate = CandidateBuilder.build(recipes: [recipe], ingredients: [:], foods: Planning.foods)[0]

        #expect(candidate.ingredients.isEmpty)
        #expect(candidate.foodGroupsGrams.isEmpty)
        #expect(candidate.nutrition.coverage == 0)
    }
}

struct PlanningConstraintCompilerTests {
    @Test func compileCarriesProfileLimitsAndTargets() {
        let profile = Planning.profile(household: 3, maxCookMinutes: 25, equipment: [.stovetop, .oven])
        let targets = [NutrientTarget(nutrient: .fiber, basis: .perDay, min: 30, priority: 2, source: .custom)]
        let constraints = Persona.vegan.constraints

        let compiled = ConstraintCompiler.compile(profile: profile, constraints: constraints, targets: targets)

        #expect(compiled.constraints == constraints)
        #expect(compiled.maxCookMinutes == 25)
        #expect(compiled.equipment == [.stovetop, .oven])
        #expect(compiled.targets == targets)
        #expect(compiled.householdSize == 3)
    }

    @Test func householdBelowOneCountsAsOne() {
        #expect(Planning.compiled(household: 0).householdSize == 1)
        #expect(Planning.compiled(household: -2).householdSize == 1)
    }

    @Test func admitsARecipeWithinEveryLimit() {
        let compiled = Planning.compiled(Persona.nutAllergy.constraints, maxCookMinutes: 40, equipment: [.stovetop])

        #expect(compiled.admits(Planning.chickenTikka, foods: Planning.foods) == .admitted(softPenalties: []))
    }

    @Test func recipeOverTheTimeCapIsExcluded() {
        let compiled = Planning.compiled(maxCookMinutes: 30)

        #expect(compiled.admits(Planning.beefRagu, foods: Planning.foods)
            == .excluded(reasons: ["Takes 60 minutes, over the 30-minute limit"]))
        #expect(compiled.admits(Planning.bulgogiBowl, foods: Planning.foods) == .admitted(softPenalties: []))
    }

    @Test func recipeNeedingMissingEquipmentIsExcluded() {
        let compiled = Planning.compiled(equipment: [.stovetop, .microwave])

        #expect(compiled.admits(Planning.salmonTraybake, foods: Planning.foods) == .excluded(reasons: ["Needs an oven"]))
    }

    @Test func emptyEquipmentMeansUnknownAndAdmitsEveryRecipe() {
        let compiled = Planning.compiled(equipment: [])

        #expect(compiled.admits(Planning.salmonTraybake, foods: Planning.foods) == .admitted(softPenalties: []))
    }

    @Test func unlabelledTahiniIsUncertainUnderANutAllergy() {
        let compiled = Planning.compiled(Persona.nutAllergy.constraints)

        guard case .uncertain(let reasons) = compiled.admits(Planning.falafelBowl, foods: Planning.foods) else {
            Issue.record("Expected an uncertain admission")
            return
        }
        #expect(reasons.contains("No tree nuts data (tahini)"))
        #expect(compiled.admits(Planning.romescoChicken, foods: Planning.foods) == .excluded(reasons: ["Contains tree nuts (almond)"]))
    }

    @Test func exclusionWinsOverUncertainty() {
        let compiled = Planning.compiled(Persona.nutAllergy.constraints, maxCookMinutes: 20)

        #expect(compiled.admits(Planning.falafelBowl, foods: Planning.foods)
            == .excluded(reasons: ["Takes 35 minutes, over the 20-minute limit"]))
    }

    @Test func softDislikeAdmitsWithAPenalty() {
        let compiled = Planning.compiled([Kitchen.constraint(.dislike(.name("mushroom")), .soft, axis: .preference)])

        #expect(compiled.admits(Planning.mushroomRisotto, foods: Planning.foods)
            == .admitted(softPenalties: ["Contains a disliked food (mushroom)"]))
    }

    @Test func snapshotIgnoresOrderIdentifiersAndDates() {
        let nut = Kitchen.constraint(.allergen(.treeNut))
        let vegan = Kitchen.constraint(.diet(.vegan), axis: .ethical)
        var renewed = DietaryConstraint(axis: .ethical, kind: .diet(.vegan), strictness: .hard, source: .user, lastConfirmed: Planning.now)
        renewed.lastConfirmed = Fixtures.date(2027, 1, 1)

        let first = Planning.compiled([nut, vegan]).snapshot
        let second = Planning.compiled([renewed, nut]).snapshot

        #expect(first == second)
        #expect(first.count == 16)
        #expect(first.allSatisfy { $0.isHexDigit })
    }

    @Test func snapshotChangesWithStrictnessAndLimits() {
        let hard = Planning.compiled([Kitchen.constraint(.allergen(.treeNut))])

        #expect(hard.snapshot != Planning.compiled([Kitchen.constraint(.allergen(.treeNut), .soft)]).snapshot)
        #expect(hard.snapshot != Planning.compiled([Kitchen.constraint(.allergen(.treeNut))], maxCookMinutes: 30).snapshot)
        #expect(hard.snapshot != Planning.compiled([]).snapshot)
    }
}

struct PlanningScorerTests {
    /// 20 minutes, Thai: chicken 300 g, rice 200 g, broccoli 100 g, optional parmesan 20 g, spinach garnish 50 g.
    private let bowl = Planning.dish(
        "Test bowl", cuisine: "Thai", servings: 2, prep: 10, cook: 10,
        [(Planning.chicken, 300), (Planning.rice, 200), (Planning.broccoli, 100)],
        optional: [(Planning.parmesan, 20)],
        garnish: [(Planning.spinach, 50)]
    )

    private var bowlPantry: [PantryItem] {
        [
            Planning.pantryItem(Planning.chicken, grams: 200, bestBy: Planning.day(2)),
            Planning.pantryItem(Planning.rice, grams: 1000),
            Planning.pantryItem(Planning.spinach, grams: 100, bestBy: Planning.day(1)),
        ]
    }

    @Test func componentsMatchHandComputedValues() {
        let scored = RecipeScorer.score(bowl, context: Planning.context(pantry: bowlPantry, maxCookMinutes: 40))
        let parts = scored.components

        // pantry covers chicken 200 of 300 and rice 200 of 200, out of 600 required grams
        #expect(Kitchen.isClose(parts.pantryOverlap, 400.0 / 600.0))
        // chicken has 2 days left; the spinach is only a garnish, so it is not used
        #expect(Kitchen.isClose(parts.expiryUrgency, 1.0 / 3.0))
        #expect(Kitchen.isClose(parts.timeFit, 0.5))
        // broccoli is the one uncovered line of three required lines
        #expect(Kitchen.isClose(parts.costProxy, 2.0 / 3.0))
        #expect(parts.novelty == 1)
        #expect(parts.taste == 0)
        // (300*0.24 + 200*0.027 + 100*0.028 + 20*0.36) / 2 = 43.7 g per serving, capped at 1
        #expect(parts.protein == 1)
        let expected: Double = 2.0 / 3.0 + 1.0 / 3.0 + 0.5 + 2.0 / 3.0 + 1
        #expect(Kitchen.isClose(scored.score, expected))
    }

    @Test func reasonCodesComeFromComponents() {
        let scored = RecipeScorer.score(bowl, context: Planning.context(pantry: bowlPantry, maxCookMinutes: 40))

        #expect(scored.reasonCodes == [
            .usesExpiring(food: Planning.chicken.id, bestBy: Planning.day(2)),
            .pantryOverlap(count: 2),
            .quick(minutes: 20),
            .varietyCuisine(cuisine: "Thai"),
        ])
    }

    @Test func expiryUrgencySumsTermsAndCapsAtOne() {
        let soon = [
            Planning.pantryItem(Planning.chicken, grams: 50, bestBy: Planning.day(1)),
            Planning.pantryItem(Planning.broccoli, grams: 50, bestBy: Planning.day(2)),
        ]
        let crowded = soon + [Planning.pantryItem(Planning.rice, grams: 50, bestBy: Planning.day(-2))]

        #expect(Kitchen.isClose(RecipeScorer.score(bowl, context: Planning.context(pantry: soon)).components.expiryUrgency, 1))
        #expect(RecipeScorer.score(bowl, context: Planning.context(pantry: crowded)).components.expiryUrgency == 1)
        let single = [Planning.pantryItem(Planning.rice, grams: 50, bestBy: Planning.day(-2))]
        #expect(RecipeScorer.score(bowl, context: Planning.context(pantry: single)).components.expiryUrgency == 1)
    }

    @Test func itemsBeyondThreeDaysOrEmptyAreNotUrgent() {
        let pantry = [
            Planning.pantryItem(Planning.chicken, grams: 300, bestBy: Planning.day(5)),
            Planning.pantryItem(Planning.broccoli, grams: 0, bestBy: Planning.day(1)),
        ]

        let scored = RecipeScorer.score(bowl, context: Planning.context(pantry: pantry))

        #expect(scored.components.expiryUrgency == 0)
        #expect(!scored.reasonCodes.contains { if case .usesExpiring = $0 { true } else { false } })
        #expect(Kitchen.isClose(scored.components.costProxy, 1.0 / 3.0))
    }

    @Test func timeFitClampsAtZeroAndANonPositiveCapGivesZero() {
        #expect(RecipeScorer.score(Planning.beefRagu, context: Planning.context(maxCookMinutes: 30)).components.timeFit == 0)
        #expect(RecipeScorer.score(bowl, context: Planning.context(maxCookMinutes: 0)).components.timeFit == 0)
        #expect(Kitchen.isClose(RecipeScorer.score(bowl, context: Planning.context(maxCookMinutes: 80)).components.timeFit, 0.75))
    }

    @Test func emptyPantryAndEmptyRecipeScoreZeroOnPantryParts() {
        let empty = CandidateBuilder.build(recipes: [Kitchen.recipe("Bare")], ingredients: [:], foods: Planning.foods)[0]

        let bare = RecipeScorer.score(empty, context: Planning.context()).components
        let noPantry = RecipeScorer.score(bowl, context: Planning.context(pantry: [])).components

        #expect(bare.pantryOverlap == 0 && bare.costProxy == 0 && bare.protein == 0)
        #expect(noPantry.pantryOverlap == 0 && noPantry.costProxy == 0 && noPantry.expiryUrgency == 0)
    }

    @Test(arguments: [(nil as Double?, 1.0), (3, 0), (14, 0), (21, 0.5), (28, 1), (60, 1)])
    func noveltyDecaysOverFourteenDaysAfterTheCooldown(daysAgo: Double?, expected: Double) {
        let recent = daysAgo.map { [bowl.recipe.id: Planning.day(-$0)] } ?? [:]

        let novelty = RecipeScorer.score(bowl, context: Planning.context(recentlyPlanned: recent)).components.novelty

        #expect(Kitchen.isClose(novelty, expected))
    }

    @Test func tasteFollowsLikesAndSkips() {
        let id = bowl.recipe.id

        #expect(RecipeScorer.score(bowl, context: Planning.context(liked: [id])).components.taste == 1)
        #expect(RecipeScorer.score(bowl, context: Planning.context(skipped: [id])).components.taste == -1)
        #expect(RecipeScorer.score(bowl, context: Planning.context(liked: [id], skipped: [id])).components.taste == 0)
    }

    @Test func varietyCuisineIsDroppedWhenTheCuisineWasPlannedThisWeek() {
        let lastWeek = RecipeScorer.score(bowl, context: Planning.context(recentCuisines: ["thai": Planning.day(-3)]))
        let longAgo = RecipeScorer.score(bowl, context: Planning.context(recentCuisines: ["Thai": Planning.day(-8)]))

        #expect(!lastWeek.reasonCodes.contains(.varietyCuisine(cuisine: "Thai")))
        #expect(longAgo.reasonCodes.contains(.varietyCuisine(cuisine: "Thai")))
    }

    @Test func underBudgetOnlyForSaveMoneyWithMostlyCoveredLines() {
        let covered = RecipeScorer.score(bowl, context: Planning.context(pantry: bowlPantry, goal: .saveMoney))
        let uncovered = RecipeScorer.score(bowl, context: Planning.context(pantry: [], goal: .saveMoney))
        let otherGoal = RecipeScorer.score(bowl, context: Planning.context(pantry: bowlPantry, goal: .maintain))

        #expect(covered.reasonCodes.contains(.underBudget))
        #expect(!uncovered.reasonCodes.contains(.underBudget))
        #expect(!otherGoal.reasonCodes.contains(.underBudget))
    }

    /// Pantry stew: half covered by expiring chicken, 40 minutes. Quick salad: nothing from the pantry, 10 minutes, liked.
    private func stewAndSalad(goal: Goal) -> (stew: Double, salad: Double) {
        let stew = Planning.dish("Pantry stew", cuisine: nil, servings: 2, prep: 10, cook: 30, [(Planning.chicken, 200), (Planning.broccoli, 200)])
        let salad = Planning.dish("Quick salad", cuisine: nil, servings: 2, prep: 10, cook: 0, [(Planning.broccoli, 200), (Planning.mushroom, 100)])
        let pantry = [Planning.pantryItem(Planning.chicken, grams: 200, bestBy: Planning.day(2))]
        let context = Planning.context(pantry: pantry, goal: goal, liked: [salad.recipe.id])
        return (RecipeScorer.score(stew, context: context).score, RecipeScorer.score(salad, context: context).score)
    }

    @Test func lessWasteLiftsThePantryRecipeAboveTheQuickOne() {
        let balanced = stewAndSalad(goal: .maintain)
        let lessWaste = stewAndSalad(goal: .lessWaste)

        // stew 0.5 + 1/3 + 1/3 + 0.5 + 1; salad 5/6 + 1 + 1
        #expect(Kitchen.isClose(balanced.stew, 8.0 / 3.0))
        #expect(Kitchen.isClose(balanced.salad, 17.0 / 6.0))
        #expect(balanced.salad > balanced.stew)
        #expect(Kitchen.isClose(lessWaste.stew, 3.5))
        #expect(lessWaste.stew > lessWaste.salad)
    }

    @Test func saveMoneyDoublesTheCostProxy() {
        let saveMoney = stewAndSalad(goal: .saveMoney)

        #expect(Kitchen.isClose(saveMoney.stew, 8.0 / 3.0 + 0.5))
        #expect(saveMoney.stew > saveMoney.salad)
    }

    @Test func moreVarietyFavoursTheRecipeNotPlannedLately() {
        let familiar = Planning.dish("Familiar", cuisine: nil, servings: 2, prep: 5, cook: 5, [(Planning.broccoli, 200)])
        let fresh = Planning.dish("Fresh", cuisine: nil, servings: 2, prep: 10, cook: 10, [(Planning.mushroom, 200)])
        func scores(_ goal: Goal) -> (Double, Double) {
            let context = Planning.context(
                pantry: [], goal: goal, recentlyPlanned: [familiar.recipe.id: Planning.day(-5)], liked: [familiar.recipe.id]
            )
            return (RecipeScorer.score(familiar, context: context).score, RecipeScorer.score(fresh, context: context).score)
        }

        let balanced = scores(.eatBetter)
        let variety = scores(.moreVariety)

        #expect(balanced.0 > balanced.1)
        #expect(variety.1 > variety.0)
        #expect(Kitchen.isClose(variety.1 - balanced.1, 1))
    }

    @Test func moreProteinFavoursTheProteinRichRecipe() {
        let lean = Planning.dish("Chicken plate", cuisine: nil, servings: 2, prep: 10, cook: 30, [(Planning.chicken, 400)])
        let light = Planning.dish("Broccoli plate", cuisine: nil, servings: 2, prep: 5, cook: 5, [(Planning.broccoli, 300)])
        func scores(_ goal: Goal) -> (Double, Double) {
            let context = Planning.context(pantry: [], goal: goal)
            return (RecipeScorer.score(lean, context: context).score, RecipeScorer.score(light, context: context).score)
        }

        let balanced = scores(.maintain)
        let protein = scores(.moreProtein)

        #expect(balanced.1 > balanced.0)
        #expect(protein.0 > protein.1)
        // 300 g broccoli at 2.8 g per 100 g over 2 servings is 4.2 g, a 0.105 protein component
        #expect(Kitchen.isClose(protein.1 - balanced.1, 0.105))
    }
}
