import LarderCore
import Testing
@testable import FeatureRecipes

@MainActor
struct TimerModelTests {
    private func tick(_ clock: ManualClock, seconds: Int = 1) async {
        for _ in 0..<seconds {
            await settle()
            clock.advance(by: .seconds(1))
        }
        await settle()
    }

    @Test func startsIdleAtTheFullTime() {
        let timer = TimerModel(seconds: 90, clock: ManualClock())
        #expect(timer.state == .idle)
        #expect(timer.remainingSeconds == 90)
        #expect(timer.totalSeconds == 90)
    }

    @Test func nonPositiveDurationsClampToOneSecond() {
        #expect(TimerModel(seconds: 0, clock: ManualClock()).totalSeconds == 1)
        #expect(TimerModel(seconds: -5, clock: ManualClock()).totalSeconds == 1)
    }

    @Test func countsDownOneSecondAtATime() async {
        let clock = ManualClock()
        let timer = TimerModel(seconds: 3, clock: clock)
        timer.start()
        #expect(timer.state == .running)
        await tick(clock)
        #expect(timer.remainingSeconds == 2)
        await tick(clock)
        #expect(timer.remainingSeconds == 1)
        #expect(timer.state == .running)
    }

    @Test func finishesOnceAndCallsBack() async {
        let clock = ManualClock()
        let timer = TimerModel(seconds: 2, clock: clock)
        var finished = 0
        timer.onFinish = { finished += 1 }
        timer.start()
        await tick(clock, seconds: 2)
        #expect(timer.state == .finished)
        #expect(timer.remainingSeconds == 0)
        #expect(finished == 1)
        clock.advance(by: .seconds(10))
        await settle()
        #expect(finished == 1)
    }

    @Test func pauseKeepsTimeLeftAndStopsCounting() async {
        let clock = ManualClock()
        let timer = TimerModel(seconds: 5, clock: clock)
        timer.start()
        await tick(clock)
        timer.pause()
        await settle()
        #expect(timer.state == .paused)
        clock.advance(by: .seconds(30))
        await settle()
        #expect(timer.remainingSeconds == 4)
        #expect(clock.sleeperCount == 0)
    }

    @Test func resumeContinuesFromTheTimeLeft() async {
        let clock = ManualClock()
        let timer = TimerModel(seconds: 5, clock: clock)
        timer.start()
        await tick(clock)
        timer.pause()
        await settle()
        clock.advance(by: .seconds(30))
        timer.start()
        await tick(clock)
        #expect(timer.remainingSeconds == 3)
        #expect(timer.state == .running)
    }

    @Test func resetReturnsToFullTimeAndIdle() async {
        let clock = ManualClock()
        let timer = TimerModel(seconds: 5, clock: clock)
        timer.start()
        await tick(clock, seconds: 2)
        timer.reset()
        await settle()
        #expect(timer.state == .idle)
        #expect(timer.remainingSeconds == 5)
        #expect(clock.sleeperCount == 0)
    }

    @Test func startingTwiceDoesNotDoubleTheRate() async {
        let clock = ManualClock()
        let timer = TimerModel(seconds: 5, clock: clock)
        timer.start()
        timer.start()
        await tick(clock)
        #expect(timer.remainingSeconds == 4)
        #expect(clock.sleeperCount == 1)
    }

    @Test func finishedTimerRestartsFromTheTop() async {
        let clock = ManualClock()
        let timer = TimerModel(seconds: 1, clock: clock)
        timer.start()
        await tick(clock)
        #expect(timer.state == .finished)
        timer.start()
        #expect(timer.state == .running)
        #expect(timer.remainingSeconds == 1)
    }

    @Test func pauseWhileIdleDoesNothing() {
        let timer = TimerModel(seconds: 5, clock: ManualClock())
        timer.pause()
        #expect(timer.state == .idle)
    }
}

@MainActor
struct CookingSessionTests {
    private let recipe = Recipe(
        title: "Chana masala", origin: .generated, servings: 4, prepMinutes: 10, cookMinutes: 25,
        steps: [
            RecipeStep(text: "Warm the oil and fry the garlic."),
            RecipeStep(text: "Add the chickpeas and simmer for 15 minutes.", timerSeconds: 900),
            RecipeStep(text: "Boil the rice for 2 minutes.", timerSeconds: 2),
            RecipeStep(text: "Serve."),
        ]
    )

    private var ingredients: [Ingredient] {
        [
            Ingredient(recipeID: recipe.id, rawText: "2 tbsp olive oil", quantity: 2, unit: .tablespoon),
            Ingredient(recipeID: recipe.id, rawText: "2 cloves garlic, minced", quantity: 2, unit: .clove),
            Ingredient(recipeID: recipe.id, rawText: "1 (400 g) can chickpeas, drained", quantity: 400, unit: .gram),
            Ingredient(recipeID: recipe.id, rawText: "1 cup rice", quantity: 1, unit: .cup),
        ]
    }

    @Test func createsTimersOnlyForStepsWithTimerSeconds() {
        let session = CookingSession(recipe: recipe, ingredients: ingredients, clock: ManualClock())
        #expect(session.timer(forStep: 0) == nil)
        #expect(session.timer(forStep: 1)?.totalSeconds == 900)
        #expect(session.timer(forStep: 2)?.totalSeconds == 2)
        #expect(session.timer(forStep: 3) == nil)
        #expect(session.timer(forStep: 9) == nil)
    }

    @Test func navigationStaysWithinTheSteps() {
        let session = CookingSession(recipe: recipe, ingredients: [], clock: ManualClock())
        #expect(session.isFirst)
        session.back()
        #expect(session.stepIndex == 0)
        session.go(to: 2)
        #expect(session.stepIndex == 2)
        session.next()
        #expect(session.isLast)
        session.next()
        #expect(session.stepIndex == 3)
        session.go(to: 99)
        #expect(session.stepIndex == 3)
        session.go(to: -4)
        #expect(session.stepIndex == 0)
    }

    @Test func emptyRecipeHasNoStepsToVisit() {
        let empty = Recipe(title: "Empty", origin: .generated, servings: 1, prepMinutes: 0, cookMinutes: 0)
        let session = CookingSession(recipe: empty, ingredients: [], clock: ManualClock())
        session.next()
        #expect(session.stepIndex == 0)
        #expect(session.ingredientSummary(forStep: 0) == nil)
    }

    @Test func timersOnOtherStepsStayVisibleOnceStarted() {
        let session = CookingSession(recipe: recipe, ingredients: [], clock: ManualClock())
        #expect(session.otherActiveTimers.isEmpty)
        session.timer(forStep: 1)?.start()
        session.go(to: 0)
        #expect(session.otherActiveTimers.map(\.step) == [1])
        session.go(to: 1)
        #expect(session.otherActiveTimers.isEmpty)
        session.stopTimers()
    }

    @Test func finishedTimerBumpsTheFinishCount() async {
        let clock = ManualClock()
        let session = CookingSession(recipe: recipe, ingredients: [], clock: clock)
        session.timer(forStep: 2)?.start()
        for _ in 0..<2 {
            await settle()
            clock.advance(by: .seconds(1))
        }
        await settle()
        #expect(session.finishCount == 1)
    }

    @Test func stopTimersResetsRunningOnes() async {
        let clock = ManualClock()
        let session = CookingSession(recipe: recipe, ingredients: [], clock: clock)
        let timer = session.timer(forStep: 1)
        timer?.start()
        await settle()
        session.stopTimers()
        await settle()
        #expect(timer?.state == .idle)
        #expect(clock.sleeperCount == 0)
    }

    @Test func summaryNamesTheIngredientsInTheStep() {
        let session = CookingSession(recipe: recipe, ingredients: ingredients, clock: ManualClock())
        #expect(session.ingredientSummary(forStep: 0) == "2 tbsp olive oil; 2 cloves garlic, minced")
        #expect(session.ingredientSummary(forStep: 1) == "1 (400 g) can chickpeas, drained")
        #expect(session.ingredientSummary(forStep: 3) == nil)
        #expect(session.ingredientSummary(forStep: 50) == nil)
    }
}

struct StepIngredientsTests {
    private let recipe = Sample.recipe("Matching")

    private func lines(_ texts: [String]) -> [Ingredient] {
        texts.map { Ingredient(recipeID: recipe.id, rawText: $0, quantity: 1, unit: .piece) }
    }

    @Test func matchesByLastWordOfTheName() {
        let found = StepIngredients.matching("Warm the oil over medium heat.", in: lines(["2 tbsp olive oil", "1 cup rice"]))
        #expect(found.map(\.rawText) == ["2 tbsp olive oil"])
    }

    @Test func matchesWholePhrase() {
        let found = StepIngredients.matching("Stir in the olive oil.", in: lines(["2 tbsp olive oil"]))
        #expect(found.count == 1)
    }

    @Test func ignoresPreparationNotesAfterTheComma() {
        let found = StepIngredients.matching("Fry the garlic until soft.", in: lines(["2 cloves garlic, minced"]))
        #expect(found.count == 1)
    }

    @Test func matchesPluralAndSingular() {
        #expect(StepIngredients.matching("Add chopped onions.", in: lines(["1 onion"])).count == 1)
        #expect(StepIngredients.matching("Crack the egg.", in: lines(["3 eggs"])).count == 1)
        #expect(StepIngredients.matching("Halve the tomatoes.", in: lines(["2 tomatoes"])).count == 1)
    }

    @Test func matchesWholeWordsOnly() {
        #expect(StepIngredients.matching("Wash your hands.", in: lines(["1 slice ham"])).isEmpty)
        #expect(StepIngredients.matching("Add the pepper.", in: lines(["1 tsp pepperoni"])).isEmpty)
    }

    @Test func skipsVeryShortNames() {
        #expect(StepIngredients.matching("Add the oi.", in: lines(["1 tsp oi"])).isEmpty)
    }

    @Test func stepWithNoIngredientsHasNoSummary() {
        #expect(StepIngredients.summary(for: "Let it rest.", in: lines(["2 eggs", "1 cup milk"])) == nil)
    }

    @Test func summaryJoinsMatchesInRecipeOrder() {
        let summary = StepIngredients.summary(for: "Whisk the milk into the eggs.", in: lines(["2 eggs", "1 cup milk"]))
        #expect(summary == "2 eggs; 1 cup milk")
    }

    @Test func caseInsensitive() {
        #expect(StepIngredients.matching("ADD THE FLOUR.", in: lines(["200 g Flour"])).count == 1)
    }
}

struct RecipeFiltersTests {
    @Test func emptyFiltersMatchEverything() {
        #expect(RecipeFilters().matches(Sample.recipe("Anything")))
        #expect(RecipeFilters().isEmpty)
    }

    @Test func recipeWithoutTagsFailsAnyTagFilter() {
        let bare = Sample.recipe("Bare", meals: [])
        #expect(!RecipeFilters(mealTypes: [.dinner]).matches(bare))
        #expect(!RecipeFilters(dietFlags: [.vegan]).matches(bare))
        #expect(!RecipeFilters(cuisine: "Thai").matches(bare))
    }

    @Test func timeLimitIsInclusive() {
        let recipe = Sample.recipe("Timed", prep: 10, cook: 20)
        #expect(RecipeFilters(maxMinutes: 30).matches(recipe))
        #expect(!RecipeFilters(maxMinutes: 29).matches(recipe))
    }
}
