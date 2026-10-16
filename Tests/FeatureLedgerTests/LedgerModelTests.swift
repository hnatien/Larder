import Foundation
import LarderCore
import Testing
@testable import FeatureLedger

@MainActor @Suite struct LedgerPlanningTests {
    @Test func planWeekSavesAnActivePlanAndArchivesThePreviousOne() async throws {
        let world = World()
        let (old, oldMeals) = await world.seed(Fixtures.plan(start: Fixtures.day(-7))) { plan in
            [Fixtures.meal(Fixtures.beefRagu, in: plan, day: 0, status: .cooked)]
        }
        let model = world.ledger()
        await model.load()
        await model.planWeek()

        let plan = try #require(model.plan)
        #expect(model.error == nil)
        #expect(plan.status == .active)
        #expect(plan.startDate == Fixtures.today)
        #expect(plan.days == 7)
        #expect(await world.plans.currentPlan() == plan)
        #expect(await world.plans.plan(old.id)?.status == .archived)
        #expect(await world.plans.meals(for: old.id) == oldMeals)
        #expect(model.meals.count == 7)
        #expect(model.meals.allSatisfy { $0.planID == plan.id })
        #expect(Set(await world.plans.meals(for: plan.id)) == Set(model.meals))
        #expect(model.verification != nil)
        #expect(model.savedPlanCount == 1)
        #expect(!model.isPlanning)
    }

    @Test func seedComesFromTheClock() async throws {
        let model = World().ledger()
        await model.planWeek()
        #expect(model.plan?.seed == UInt64(Fixtures.now.timeIntervalSince1970))
    }

    @Test func freeUserWithAFreeWeekGetsAPlanAndUsesIt() async {
        let world = World(isPlus: false, freeWeekAvailable: true)
        let model = world.ledger()
        await model.planWeek()
        #expect(model.plan != nil)
        #expect(!model.paywallRequested)
        #expect(await world.entitlements.marks == 1)
    }

    @Test func freeUserWithoutAFreeWeekGetsThePaywallAndNoPlan() async {
        let world = World(isPlus: false, freeWeekAvailable: false)
        let model = world.ledger()
        await model.planWeek()
        #expect(model.paywallRequested)
        #expect(model.plan == nil)
        #expect(model.error == nil)
        #expect(await world.plans.saveCount == 0)
        #expect(await world.entitlements.marks == 0)
        #expect(await world.assistant.explainRequests.isEmpty)
    }

    @Test func plusUserNeverTouchesTheFreeWeek() async {
        let world = World(isPlus: true, freeWeekAvailable: true)
        let model = world.ledger()
        await model.planWeek()
        await model.replan(keepingLocked: true)
        #expect(model.plan != nil)
        #expect(await world.entitlements.marks == 0)
        #expect(await world.entitlements.freeWeekChecks == 0)
    }

    @Test func freeUserCannotReplanOnceTheFreeWeekIsUsed() async {
        let world = World(isPlus: false, freeWeekAvailable: true)
        let model = world.ledger()
        await model.planWeek()
        let first = model.plan
        await model.replan(keepingLocked: true)
        #expect(model.paywallRequested)
        #expect(model.plan == first)
        #expect(await world.entitlements.marks == 1)
    }

    @Test func planWeekWithoutAProfileReportsNotFoundAndSavesNothing() async {
        var world = World(isPlus: false, freeWeekAvailable: true)
        world.profiles.stored = nil
        let model = world.ledger()
        await model.planWeek()
        #expect(model.error == .notFound)
        #expect(model.plan == nil)
        #expect(await world.plans.saveCount == 0)
        #expect(await world.entitlements.marks == 0)
    }

    @Test func lockedMealsSurviveAReplan() async throws {
        let world = World()
        let model = world.ledger()
        await model.planWeek()
        let first = try #require(model.plan)
        let target = try #require(model.meals.first { $0.leftoverOf == nil && $0.date == Fixtures.day(3) }
            ?? model.meals.first { $0.leftoverOf == nil })
        await model.lock(target)

        await model.replan(keepingLocked: true)

        let second = try #require(model.plan)
        #expect(second.id != first.id)
        let kept = try #require(model.meals.first { $0.id == target.id })
        #expect(kept.recipeID == target.recipeID)
        #expect(kept.date == target.date)
        #expect(kept.isLocked)
        #expect(kept.planID == second.id)
        #expect(await world.plans.meals(for: first.id).contains { $0.id == target.id } == false)
        #expect(await world.plans.plan(first.id)?.status == .archived)
    }

    @Test func replanWithoutKeepingLockedDropsThem() async throws {
        let world = World()
        let model = world.ledger()
        await model.planWeek()
        let target = try #require(model.meals.first { $0.leftoverOf == nil })
        await model.lock(target)
        await model.replan(keepingLocked: false)
        #expect(!model.meals.contains { $0.id == target.id })
        #expect(model.meals.count == 7)
    }

    @Test func loadWithoutAPlanLeavesTheLedgerEmpty() async {
        let model = World().ledger()
        await model.load()
        #expect(model.plan == nil)
        #expect(model.days.isEmpty)
        #expect(model.verification == nil)
        #expect(model.balanceSentence == nil)
        #expect(model.error == nil)
    }
}

@MainActor @Suite struct LedgerExplainTests {
    @Test func consentRequiredLeavesNoExplanationAndNoError() async {
        let world = World(explain: .failure(.consentRequired))
        let model = world.ledger()
        await model.planWeek()
        #expect(model.plan != nil)
        #expect(model.explanation == nil)
        #expect(model.error == nil)
        await model.requestExplanation()
        #expect(model.explanation == nil)
        #expect(model.error == nil)
        #expect(await world.assistant.explainRequests.count == 2)
    }

    @Test func plusRequiredLeavesNoExplanationAndNoError() async {
        let world = World(explain: .failure(.plusRequired))
        let model = world.ledger()
        await model.planWeek()
        await model.requestExplanation()
        #expect(model.explanation == nil)
        #expect(model.error == nil)
    }

    @Test func otherFailuresSurfaceOnlyAfterTheUserAsks() async {
        let world = World(explain: .failure(.assistantUnavailable))
        let model = world.ledger()
        await model.planWeek()
        #expect(model.error == nil)
        #expect(model.plan != nil)
        await model.requestExplanation()
        #expect(model.error == .assistantUnavailable)
        #expect(model.showsExplanation)
    }

    @Test func explainSendsTitlesReasonsAndFoodNames() async throws {
        let notes = PlanExplanation(summary: "Spinach first.", mealNotes: [.init(mealIndex: 1, text: "Uses the spinach.")])
        let world = World(explain: .success(notes))
        let expiring = ReasonCode.usesExpiring(food: Fixtures.spinach.id, bestBy: Fixtures.day(1))
        let (_, meals) = await world.seed { plan in
            [
                Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0, reasons: [.pantryOverlap(count: 3)]),
                Fixtures.meal(Fixtures.spinachOmelette, in: plan, day: 2, reasons: [expiring]),
            ]
        }
        let model = world.ledger()
        await model.load()
        await model.requestExplanation()

        let request = try #require(await world.assistant.explainRequests.last)
        #expect(request.meals.map(\.recipeTitle) == ["Red lentil soup", "Spinach omelette"])
        #expect(request.meals.map(\.dayOffset) == [0, 2])
        #expect(request.meals[1].reasonCodes == [expiring])
        #expect(request.foodNames == [Fixtures.spinach.id: Fixtures.spinach.name])
        #expect(model.explanation == notes)
        #expect(model.explanationNote(for: meals[1]) == "Uses the spinach.")
        #expect(model.explanationNote(for: meals[0]) == nil)
    }
}

@MainActor @Suite struct LedgerMealActionTests {
    let world = World()

    func loaded(_ meals: @escaping (MealPlan) -> [PlannedMeal]) async -> (LedgerModel, [PlannedMeal]) {
        let (_, seeded) = await world.seed(meals: meals)
        let model = world.ledger()
        await model.load()
        return (model, seeded)
    }

    @Test func swapUpdatesRecipeHistoryAndVerification() async throws {
        let (model, meals) = await loaded { plan in
            [
                Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0),
                Fixtures.meal(Fixtures.beefRagu, in: plan, day: 1),
            ]
        }
        let before = try #require(model.verification)
        await model.loadSwapCandidates(for: meals[0])
        let option = try #require(model.swapCandidates.first)
        #expect(!model.swapCandidates.contains { [Fixtures.lentilSoup.recipe.id, Fixtures.beefRagu.recipe.id].contains($0.recipeID) })

        await model.swap(meals[0], with: option)

        let swapped = try #require(model.meals.first { $0.id == meals[0].id })
        #expect(swapped.recipeID == option.recipeID)
        #expect(swapped.swapHistory == [Fixtures.lentilSoup.recipe.id])
        #expect(swapped.reasonCodes == option.reasonCodes)
        #expect(await world.plans.meals(for: meals[0].planID).first { $0.id == meals[0].id } == swapped)
        #expect(model.swapCandidates.isEmpty)

        let catalogue = try await world.service().catalogue()
        let expected = PlanVerifier.verify(
            meals: model.meals,
            candidates: catalogue.candidates,
            foods: catalogue.foods,
            constraints: [],
            targets: NutrientTargets.defaults(for: Fixtures.profile(), constraints: [], referenceYear: 2026),
            days: 7,
            householdSize: 2,
            slots: Set(model.meals.map(\.slot))
        )
        #expect(model.verification == expected)
        #expect(model.verification != before)
    }

    @Test func swappingACookedMealCarriesItsLeftovers() async throws {
        let (model, meals) = await loaded { plan in
            let cooked = Fixtures.meal(Fixtures.chickpeaCurry, in: plan, day: 0, servings: 4)
            return [cooked, Fixtures.meal(Fixtures.chickpeaCurry, in: plan, day: 1, leftoverOf: cooked.id, reasons: [.leftoverOf(meal: cooked.id)])]
        }
        await model.loadSwapCandidates(for: meals[0])
        let option = try #require(model.swapCandidates.first)
        await model.swap(meals[0], with: option)
        let leftover = try #require(model.meals.first { $0.id == meals[1].id })
        #expect(leftover.recipeID == option.recipeID)
        #expect(leftover.leftoverOf == meals[0].id)
    }

    @Test func swappingToTheSameRecipeChangesNothing() async throws {
        let (model, meals) = await loaded { plan in [Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0)] }
        let catalogue = try await world.service().catalogue(for: [Fixtures.lentilSoup.recipe.id])
        let same = ScoredRecipe(
            candidate: catalogue.candidates[0],
            score: 1,
            components: ScoreComponents(pantryOverlap: 0, expiryUrgency: 0, timeFit: 0, costProxy: 0, novelty: 0, taste: 0, protein: 0),
            reasonCodes: []
        )
        await model.swap(meals[0], with: same)
        #expect(model.meals == meals)
    }

    @Test func skipDimsTheMealAndTakesItOffTheShelf() async throws {
        let (model, meals) = await loaded { plan in
            [Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0), Fixtures.meal(Fixtures.beefRagu, in: plan, day: 1)]
        }
        let before = model.verification
        await model.skip(meals[1])
        #expect(model.meals.first { $0.id == meals[1].id }?.status == .skipped)
        #expect(await world.plans.meals(for: meals[1].planID).first { $0.id == meals[1].id }?.status == .skipped)
        #expect(model.verification != before)
        #expect(model.error == nil)
    }

    @Test func markCookedSetsStatus() async {
        let (model, meals) = await loaded { plan in [Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0)] }
        await model.markCooked(meals[0])
        #expect(model.meals[0].status == .cooked)
        #expect(await world.plans.meals(for: meals[0].planID)[0].status == .cooked)
    }

    @Test func lockAndUnlockPersist() async {
        let (model, meals) = await loaded { plan in [Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0)] }
        await model.lock(meals[0])
        #expect(model.meals[0].isLocked)
        #expect(await world.plans.meals(for: meals[0].planID)[0].isLocked)
        await model.unlock(meals[0])
        #expect(!model.meals[0].isLocked)
    }

    @Test func failedWriteKeepsTheMealAsItWas() async {
        let (model, meals) = await loaded { plan in [Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0)] }
        await world.plans.setFailWrites(true)
        await model.skip(meals[0])
        #expect(model.meals[0].status == .planned)
        #expect(model.error == .storageFailure)
    }

    @Test func moveChangesTheDate() async {
        let (model, meals) = await loaded { plan in [Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0)] }
        await model.moveMeal(meals[0], to: Fixtures.day(4))
        #expect(model.meals[0].date == Fixtures.day(4))
        #expect(await world.plans.meals(for: meals[0].planID)[0].date == Fixtures.day(4))
        #expect(model.days[4].meals.map(\.id) == [meals[0].id])
        #expect(model.days[0].openSlots == [.dinner])
    }

    @Test func moveOntoATakenSlotTradesPlaces() async {
        let (model, meals) = await loaded { plan in
            [Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0), Fixtures.meal(Fixtures.beefRagu, in: plan, day: 2)]
        }
        await model.moveMeal(meals[0], to: Fixtures.day(2))
        #expect(model.meals.first { $0.id == meals[0].id }?.date == Fixtures.day(2))
        #expect(model.meals.first { $0.id == meals[1].id }?.date == Fixtures.day(0))
    }

    @Test func leftoverTagCountsFromTheCookedMeal() async throws {
        let (model, meals) = await loaded { plan in
            let cooked = Fixtures.meal(Fixtures.chickpeaCurry, in: plan, day: 0, servings: 4)
            return [cooked, Fixtures.meal(Fixtures.chickpeaCurry, in: plan, day: 1, leftoverOf: cooked.id)]
        }
        let days = model.days
        #expect(days[0].meals.first?.leftoverTag == nil)
        let leftover = try #require(days[1].meals.first)
        #expect(leftover.id == meals[1].id)
        #expect(leftover.leftoverTag == "Chickpea and spinach curry, day 2 of 4")
        #expect(leftover.title == "Chickpea and spinach curry")
        #expect(leftover.minutes == 45)
    }

    @Test func leftoverWithoutItsCookedMealHasNoTag() async {
        let (model, _) = await loaded { plan in
            [Fixtures.meal(Fixtures.chickpeaCurry, in: plan, day: 1, leftoverOf: PlannedMealID())]
        }
        #expect(model.days[1].meals.first?.leftoverTag == nil)
    }

    @Test func removeLeftoverDropsItAndGivesServingsBack() async throws {
        let (model, meals) = await loaded { plan in
            let cooked = Fixtures.meal(Fixtures.chickpeaCurry, in: plan, day: 0, servings: 4)
            return [cooked, Fixtures.meal(Fixtures.chickpeaCurry, in: plan, day: 1, servings: 2, leftoverOf: cooked.id)]
        }
        await model.removeLeftover(meals[1])
        #expect(model.meals.map(\.id) == [meals[0].id])
        #expect(model.meals[0].servings == 2)
        #expect(await world.plans.meals(for: meals[0].planID).map(\.id) == [meals[0].id])
        #expect(model.days[1].openSlots == [.dinner])
    }

    @Test func removeLeftoverIgnoresACookedMeal() async {
        let (model, meals) = await loaded { plan in [Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0)] }
        await model.removeLeftover(meals[0])
        #expect(model.meals == meals)
    }

    @Test func daysListEveryDayWithTodayAndSlotsInOrder() async {
        let (model, meals) = await loaded { plan in
            [
                Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0, slot: .dinner),
                Fixtures.meal(Fixtures.spinachOmelette, in: plan, day: 0, slot: .lunch),
            ]
        }
        let days = model.days
        #expect(days.count == 7)
        #expect(days.map(\.isToday) == [true, false, false, false, false, false, false])
        #expect(days[0].meals.map(\.id) == [meals[1].id, meals[0].id])
        #expect(days[0].openSlots.isEmpty)
        #expect(days[1].meals.isEmpty)
        #expect(days[1].openSlots == [.dinner])
    }

    @Test func fillingAnOpenSlotAddsAMeal() async throws {
        let (model, _) = await loaded { plan in [Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0)] }
        await model.loadCandidates(forOpenSlot: .dinner, on: Fixtures.day(3))
        let option = try #require(model.swapCandidates.first)
        await model.fill(.dinner, on: Fixtures.day(3), with: option)
        #expect(model.days[3].meals.map(\.meal.recipeID) == [option.recipeID])
        #expect(model.days[3].openSlots.isEmpty)
        #expect(await world.plans.meals(for: model.meals[0].planID).count == 2)
    }

    @Test func reasonsRenderFromTheMealsCodes() async {
        let (model, meals) = await loaded { plan in
            [Fixtures.meal(Fixtures.lentilSoup, in: plan, day: 0, reasons: [.quick(minutes: 20), .underBudget])]
        }
        #expect(model.reasons(for: meals[0]) == ["On the table in 20 minutes", "Easy on the budget"])
        #expect(model.reasons(for: meals[0], limit: 1) == ["On the table in 20 minutes"])
    }
}

@MainActor @Suite struct LedgerShelfTests {
    @Test func balanceSentenceComesFromVerification() async throws {
        let world = World()
        await world.seed { plan in [Fixtures.meal(Fixtures.beefRagu, in: plan, day: 0)] }
        let model = world.ledger()
        await model.load()
        let balance = try #require(model.shelfBalance)
        #expect(model.balanceSentence == LedgerCopy.balanceSentence(for: balance))
        #expect(balance.groupsLight.first == .dairy)
        #expect(model.balanceSentence == "Light on dairy this week. A handful in two dinners would do it.")
    }

    @Test func averagesStayHiddenUnlessNumbersAreOn() async {
        let world = World()
        await world.seed { plan in [Fixtures.meal(Fixtures.beefRagu, in: plan, day: 0)] }
        let model = world.ledger()
        await model.load()
        #expect(model.averages.isEmpty)
    }

    @Test func averagesListEnergyProteinFibreSodiumWhenNumbersAreOn() async {
        var world = World()
        world.profiles.stored = Fixtures.profile(showsNumbers: true)
        await world.seed { plan in [Fixtures.meal(Fixtures.beefRagu, in: plan, day: 0)] }
        let model = world.ledger()
        await model.load()
        #expect(model.averages.map(\.nutrient) == [.energy, .protein, .fiber, .sodium])
    }
}
