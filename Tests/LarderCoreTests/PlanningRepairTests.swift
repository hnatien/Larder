import Foundation
import Testing
@testable import LarderCore

/// Midnight `offset` days from the plan start.
private func planDay(_ offset: Int) -> Date {
    Planning.calendar.date(byAdding: .day, value: offset, to: Planning.start) ?? Planning.start
}

/// `result` with the meals in `ids` set to `status`.
private func marking(_ result: PlanResult, _ ids: Set<PlannedMealID>, as status: MealStatus) -> PlanResult {
    var result = result
    result.meals = result.meals.map { meal in
        var meal = meal
        if ids.contains(meal.id) { meal.status = status }
        return meal
    }
    return result
}

/// A hand-built plan over `days` from the plan start holding `meals`.
private func handPlan(_ meals: (MealPlanID) -> [PlannedMeal], days: Int) -> PlanResult {
    let id = MealPlanID()
    return PlanResult(
        plan: MealPlan(id: id, startDate: Planning.start, days: days, constraintsSnapshot: "", solverVersion: "test", seed: 1, status: .active),
        meals: meals(id),
        unfilledSlots: [],
        breakdown: PlanScoreBreakdown(mealScoreTotal: 0, nutrientPenalty: 0, varietyPenalty: 0, objective: 0),
        verification: VerificationReport(hardViolations: [], nutrientNotes: [], shelfBalance: ShelfBalance(levels: [:]))
    )
}

private func meal(
    _ candidate: RecipeCandidate,
    _ plan: MealPlanID,
    day: Int,
    servings: Int = 2,
    leftoverOf: PlannedMealID? = nil,
    status: MealStatus = .planned
) -> PlannedMeal {
    PlannedMeal(
        planID: plan, date: planDay(day), slot: .dinner, recipeID: candidate.recipe.id, servings: servings,
        leftoverOf: leftoverOf, status: status
    )
}

/// What two repairs are compared on.
private func signature(_ repair: PlanRepair) -> [String] {
    repair.result.meals.map { meal in
        "\(meal.id.rawValue)|\(meal.date.timeIntervalSince1970)|\(meal.recipeID.rawValue)|\(meal.servings)|\(meal.leftoverOf?.rawValue.uuidString ?? "-")"
    }
}

private func hasCause(_ meal: PlannedMeal, _ cause: RepairCause) -> Bool {
    meal.reasonCodes.contains(.replacedBecause(cause: cause))
}

struct PlanningRepairTests {
    @Test(arguments: Array(UInt64(1)...20))
    func oneSkipChangesAtMostTwoMeals(seed: UInt64) throws {
        let request = Planning.request(seed: seed)
        let planned = WeekPlanner.plan(request)
        let skipped = try #require(planned.meals.first { $0.date == planDay(2) })
        let cooked = Set(planned.meals.filter { $0.date < planDay(2) }.map(\.id))
        let current = marking(marking(planned, cooked, as: .cooked), [skipped.id], as: .skipped)

        let repair = PlanRepairer.repair(current, today: planDay(2), events: PlanEvents(skipped: [skipped.id], cooked: cooked), request: request)

        #expect(repair.changes.count <= 2, "\(repair.changes)")
        #expect(repair.result.meals.first { $0.id == skipped.id }?.status == .skipped)
        #expect(repair.result.verification.hardViolations.isEmpty)
    }

    @Test(arguments: Array(UInt64(1)...5))
    func searchWinsBackTheEnergyBandASkipLost(seed: UInt64) throws {
        let planned = WeekPlanner.plan(Planning.request(household: 2, targets: [], seed: seed))
        let probe = NutrientTarget(nutrient: .energy, basis: .perDay, min: 1, priority: 3, source: .custom)
        let energy = PlanVerifier.verify(
            meals: planned.meals, candidates: Planning.candidates, foods: Planning.foods, constraints: [], targets: [probe],
            days: 7, householdSize: 2, slots: [.dinner]
        ).nutrientNotes[0].totalPerDay
        let coverage = MealSlotShare.coverage(slots: [.dinner])
        let floor = NutrientTarget(nutrient: .energy, basis: .perDay, min: energy * 0.97 / coverage, priority: 3, source: .custom)
        let skipped = try #require(planned.meals.first { $0.date == planDay(3) && $0.leftoverOf == nil })
        let cooked = Set(planned.meals.filter { $0.date < planDay(3) }.map(\.id))
        let current = marking(marking(planned, cooked, as: .cooked), [skipped.id], as: .skipped)

        let repair = PlanRepairer.repair(
            current, today: planDay(3), events: PlanEvents(skipped: [skipped.id], cooked: cooked),
            request: Planning.request(household: 2, targets: [floor], seed: seed)
        )

        #expect(repair.result.verification.nutrientNotes.first?.status == .within)
        #expect(repair.changes.contains { $0.cause == .balance })
        // the refill, plus one swap that may carry its leftover's day with it
        #expect(repair.changes.count <= 3, "\(repair.changes)")
        #expect(repair.result.meals.filter { $0.date < planDay(3) } == current.meals.filter { $0.date < planDay(3) })
    }

    @Test func nothingHappenedChangesNothing() {
        let request = Planning.request(seed: 3)
        let planned = WeekPlanner.plan(request)

        let repair = PlanRepairer.repair(planned, today: planDay(0), events: PlanEvents(), request: request)

        #expect(repair.changes.isEmpty)
        #expect(repair.result.meals == planned.meals)
    }

    @Test(arguments: Persona.allCases, Array(UInt64(1)...20))
    func repairKeepsEveryHardConstraint(persona: Persona, seed: UInt64) throws {
        let request = Planning.request(persona.constraints, seed: seed, pantry: Planning.pantry.filter { $0.foodID != Planning.chicken.id })
        let planned = WeekPlanner.plan(Planning.request(persona.constraints, seed: seed))
        let skipped = try #require(planned.meals.first { $0.date == planDay(3) })

        let repair = PlanRepairer.repair(
            marking(planned, [skipped.id], as: .skipped),
            today: planDay(2),
            events: PlanEvents(skipped: [skipped.id], ranOut: [Planning.chicken.id]),
            request: request
        )

        #expect(repair.result.verification.hardViolations.isEmpty)
        for meal in repair.result.meals {
            let candidate = Planning.recipe(meal.recipeID)
            let verdict = candidate.map {
                ConstraintFilter().verdict(recipe: $0.recipe, ingredients: $0.ingredients, foods: Planning.foods, constraints: persona.constraints)
            }
            #expect(verdict == .pass(softPenalties: []), "\(candidate?.recipe.title ?? "missing") after repair for \(persona)")
        }
        let cooked = repair.result.meals.filter { $0.leftoverOf == nil }.map(\.recipeID)
        #expect(Set(cooked).count == cooked.count)
    }

    @Test func skippedSourceRemovesItsLeftoverAndTheSlotRefills() throws {
        let request = Planning.request(
            candidates: [Planning.chickpeaCurry, Planning.bulgogiBowl, Planning.tofuBowl], household: 4, days: 3,
            liked: [Planning.chickpeaCurry.recipe.id]
        )
        let planned = WeekPlanner.plan(request)
        let source = try #require(planned.meals.first { $0.recipeID == Planning.chickpeaCurry.recipe.id && $0.leftoverOf == nil })
        let leftover = try #require(planned.meals.first { $0.leftoverOf == source.id })

        let repair = PlanRepairer.repair(
            marking(planned, [source.id], as: .skipped), today: source.date, events: PlanEvents(skipped: [source.id]), request: request
        )

        #expect(!repair.result.meals.contains { $0.leftoverOf == source.id })
        let refill = try #require(repair.result.meals.first { $0.id == leftover.id })
        #expect(refill.recipeID != Planning.chickpeaCurry.recipe.id)
        #expect(refill.leftoverOf == nil)
        #expect(refill.date == leftover.date)
        #expect(refill.servings == 4)
        #expect(refill.reasonCodes.first == .replacedBecause(cause: .skipped))
        #expect(repair.changes.contains(PlanChange(
            mealID: leftover.id, date: leftover.date, slot: .dinner, recipeID: refill.recipeID,
            action: .replaced(previous: Planning.chickpeaCurry.recipe.id), cause: .skipped
        )))
    }

    @Test func skippedSourceWithNothingToRefillJustLosesItsLeftover() throws {
        let request = Planning.request(candidates: [Planning.chickpeaCurry], household: 4, days: 2)
        let planned = WeekPlanner.plan(request)
        let source = try #require(planned.meals.first { $0.leftoverOf == nil })
        let leftover = try #require(planned.meals.first { $0.leftoverOf == source.id })

        let repair = PlanRepairer.repair(
            marking(planned, [source.id], as: .skipped), today: source.date, events: PlanEvents(skipped: [source.id]), request: request
        )

        #expect(repair.result.meals.map(\.id) == [source.id])
        #expect(repair.changes == [PlanChange(
            mealID: leftover.id, date: leftover.date, slot: .dinner, recipeID: leftover.recipeID, action: .removed, cause: .skipped
        )])
        #expect(repair.result.unfilledSlots.map(\.date) == [leftover.date])
    }

    @Test func pastUncookedMealMovesToTheNextFreeDayWhenThePantryCoversIt() throws {
        let covered = [
            Planning.pantryItem(Planning.tofu, grams: 300), Planning.pantryItem(Planning.rice, grams: 150),
            Planning.pantryItem(Planning.broccoli, grams: 200), Planning.pantryItem(Planning.oliveOil, grams: 15),
        ]
        let current = handPlan({ plan in
            [meal(Planning.tofuBowl, plan, day: 0), meal(Planning.beanTacos, plan, day: 1), meal(Planning.bulgogiBowl, plan, day: 3)]
        }, days: 4)
        let uncooked = current.meals[0]

        let repair = PlanRepairer.repair(
            current, today: planDay(1), events: PlanEvents(),
            request: Planning.request(household: 2, days: 4, pantry: covered)
        )

        let moved = try #require(repair.result.meals.first { $0.id == uncooked.id })
        #expect(moved.date == planDay(2))
        #expect(moved.recipeID == uncooked.recipeID)
        #expect(moved.reasonCodes.first == .movedFrom(date: planDay(0)))
        #expect(repair.changes == [PlanChange(
            mealID: uncooked.id, date: planDay(2), slot: .dinner, recipeID: uncooked.recipeID, action: .moved(from: planDay(0)), cause: .notCooked
        )])
    }

    @Test func pastUncookedMealIsDroppedWhenThePantryNoLongerCoversIt() throws {
        let short = [
            Planning.pantryItem(Planning.tofu, grams: 100), Planning.pantryItem(Planning.rice, grams: 150),
            Planning.pantryItem(Planning.broccoli, grams: 200), Planning.pantryItem(Planning.oliveOil, grams: 15),
        ]
        let current = handPlan({ plan in
            [meal(Planning.tofuBowl, plan, day: 0), meal(Planning.beanTacos, plan, day: 1), meal(Planning.bulgogiBowl, plan, day: 3)]
        }, days: 4)
        let uncooked = current.meals[0]

        let repair = PlanRepairer.repair(
            current, today: planDay(1), events: PlanEvents(),
            request: Planning.request(household: 2, days: 4, pantry: short)
        )

        #expect(!repair.result.meals.contains { $0.id == uncooked.id })
        #expect(repair.changes == [PlanChange(
            mealID: uncooked.id, date: planDay(0), slot: .dinner, recipeID: uncooked.recipeID, action: .removed, cause: .notCooked
        )])
        #expect(repair.result.unfilledSlots.map(\.date) == [planDay(2)])
    }

    @Test func expiredPantryDoesNotCoverAPastMeal() {
        let stale = [
            Planning.pantryItem(Planning.tofu, grams: 300, bestBy: planDay(0)), Planning.pantryItem(Planning.rice, grams: 150),
            Planning.pantryItem(Planning.broccoli, grams: 200), Planning.pantryItem(Planning.oliveOil, grams: 15),
        ]
        let current = handPlan({ plan in [meal(Planning.tofuBowl, plan, day: 0)] }, days: 3)

        let repair = PlanRepairer.repair(current, today: planDay(1), events: PlanEvents(), request: Planning.request(household: 2, days: 3, pantry: stale))

        #expect(repair.result.meals.isEmpty)
        #expect(repair.changes.map(\.action) == [.removed])
    }

    @Test func pastUncookedMealWithNoFreeDayIsDropped() {
        let current = handPlan({ plan in
            [meal(Planning.tofuBowl, plan, day: 0), meal(Planning.beanTacos, plan, day: 1), meal(Planning.bulgogiBowl, plan, day: 2)]
        }, days: 3)

        let repair = PlanRepairer.repair(current, today: planDay(1), events: PlanEvents(), request: Planning.request(household: 2, days: 3))

        #expect(repair.result.meals.map(\.recipeID) == [Planning.beanTacos.recipe.id, Planning.bulgogiBowl.recipe.id])
        #expect(repair.changes.map(\.action) == [.removed])
    }

    @Test func repairDaysAfterTheWeekEndedDropsItsUncookedMeals() {
        let current = handPlan({ plan in [meal(Planning.tofuBowl, plan, day: 0), meal(Planning.beanTacos, plan, day: 2)] }, days: 3)

        let repair = PlanRepairer.repair(current, today: planDay(5), events: PlanEvents(), request: Planning.request(household: 2, days: 3))

        #expect(repair.result.meals.isEmpty)
        #expect(repair.changes.map(\.action) == [.removed, .removed])
        #expect(repair.result.unfilledSlots.isEmpty)
    }

    @Test func repairBeforeTheWeekStartsChangesNothing() {
        let current = handPlan({ plan in [meal(Planning.tofuBowl, plan, day: 0), meal(Planning.beanTacos, plan, day: 1)] }, days: 3)

        let repair = PlanRepairer.repair(current, today: planDay(-2), events: PlanEvents(), request: Planning.request(household: 2, days: 3))

        #expect(repair.changes.isEmpty)
        #expect(Set(repair.result.meals.map(\.id)) == Set(current.meals.map(\.id)))
    }

    @Test func movedSourceTakesItsLeftoverAlong() throws {
        let stocked = Planning.chickpeaCurry.ingredients.compactMap { line in
            line.foodID.flatMap { Planning.foods[$0] }.map { Planning.pantryItem($0, grams: (line.gramsResolved ?? 0) + 1) }
        }
        let current = handPlan({ plan in
            let source = meal(Planning.chickpeaCurry, plan, day: 0, servings: 8)
            return [source, meal(Planning.chickpeaCurry, plan, day: 1, servings: 4, leftoverOf: source.id), meal(Planning.beanTacos, plan, day: 3, servings: 4)]
        }, days: 4)
        let source = current.meals[0]
        let leftover = current.meals[1]

        let repair = PlanRepairer.repair(current, today: planDay(1), events: PlanEvents(), request: Planning.request(household: 4, days: 4, pantry: stocked))

        #expect(repair.result.meals.first { $0.id == source.id }?.date == planDay(1))
        let moved = try #require(repair.result.meals.first { $0.id == leftover.id })
        #expect(moved.date == planDay(2))
        #expect(moved.leftoverOf == source.id)
        #expect(Set(repair.changes.map(\.action)) == [.moved(from: planDay(0)), .moved(from: planDay(1))])
    }

    @Test func mealThatLostAFoodIsReplacedWithoutIt() throws {
        let request = Planning.request(seed: 4)
        let planned = WeekPlanner.plan(request)
        let target = try #require(planned.meals.first { meal in
            meal.leftoverOf == nil && meal.date >= planDay(1)
                && Planning.recipe(meal.recipeID)?.ingredients.contains { $0.foodID == Planning.chicken.id } == true
        })
        var gone = request
        gone.context.pantry.removeAll { $0.foodID == Planning.chicken.id }

        let repair = PlanRepairer.repair(planned, today: planDay(1), events: PlanEvents(ranOut: [Planning.chicken.id]), request: gone)

        let replaced = try #require(repair.result.meals.first { $0.id == target.id })
        #expect(replaced.recipeID != target.recipeID)
        #expect(Planning.recipe(replaced.recipeID)?.ingredients.contains { $0.foodID == Planning.chicken.id } == false)
        #expect(hasCause(replaced, .outOfStock(food: Planning.chicken.id)))
        #expect(repair.changes.contains { $0.mealID == target.id && $0.cause == .outOfStock(food: Planning.chicken.id) })
    }

    @Test func mealKeepsAFoodThatWasRestocked() throws {
        let restocked = Planning.pantry.filter { $0.foodID != Planning.chicken.id } + [Planning.pantryItem(Planning.chicken, grams: 1200)]
        let request = Planning.request(seed: 4, pantry: restocked)
        let planned = WeekPlanner.plan(request)

        let repair = PlanRepairer.repair(planned, today: planDay(0), events: PlanEvents(ranOut: [Planning.chicken.id]), request: request)

        #expect(planned.meals.contains { Planning.recipe($0.recipeID)?.ingredients.contains { $0.foodID == Planning.chicken.id } == true })
        #expect(repair.changes.isEmpty)
    }

    @Test func expiredFoodReplacesTheMealThatCountedOnIt() throws {
        let current = handPlan({ plan in
            [meal(Planning.beanTacos, plan, day: 0, status: .cooked), meal(Planning.spinachOmelette, plan, day: 1), meal(Planning.tofuBowl, plan, day: 2)]
        }, days: 3)
        let pantry = [Planning.pantryItem(Planning.spinach, grams: 200, bestBy: planDay(0))]

        let repair = PlanRepairer.repair(
            current, today: planDay(1), events: PlanEvents(expired: [Planning.spinach.id]),
            request: Planning.request(household: 2, days: 3, pantry: pantry)
        )

        let replaced = try #require(repair.result.meals.first { $0.id == current.meals[1].id })
        #expect(replaced.recipeID != Planning.spinachOmelette.recipe.id)
        #expect(hasCause(replaced, .expired(food: Planning.spinach.id)))
        #expect(repair.result.meals.first { $0.id == current.meals[0].id } == current.meals[0])
    }

    @Test func cookedLockedAndPastMealsNeverChange() {
        let current = handPlan({ plan in
            var locked = meal(Planning.spinachOmelette, plan, day: 2)
            locked.isLocked = true
            return [meal(Planning.beanTacos, plan, day: 0, status: .cooked), meal(Planning.bulgogiBowl, plan, day: 1, status: .skipped), locked]
        }, days: 3)
        let pantry = [Planning.pantryItem(Planning.spinach, grams: 1, bestBy: planDay(-5))]

        let repair = PlanRepairer.repair(
            current, today: planDay(2), events: PlanEvents(expired: [Planning.spinach.id]),
            request: Planning.request(household: 2, days: 3, pantry: pantry)
        )

        #expect(repair.changes.isEmpty)
        #expect(repair.result.meals == current.meals)
    }

    @Test func eventsSetTheMealStatuses() {
        let current = handPlan({ plan in [meal(Planning.beanTacos, plan, day: 0), meal(Planning.tofuBowl, plan, day: 1)] }, days: 2)

        let repair = PlanRepairer.repair(
            current, today: planDay(0), events: PlanEvents(skipped: [current.meals[1].id], cooked: [current.meals[0].id]),
            request: Planning.request(household: 2, days: 2)
        )

        #expect(repair.result.meals.map(\.status) == [.cooked, .skipped])
        #expect(repair.changes.isEmpty)
    }

    @Test(arguments: Array(UInt64(1)...5))
    func repairIsDeterministicForASeed(seed: UInt64) throws {
        let request = Planning.request(seed: seed, pantry: Planning.pantry.filter { $0.foodID != Planning.chicken.id })
        let planned = WeekPlanner.plan(Planning.request(seed: seed))
        let skipped = try #require(planned.meals.first { $0.date == planDay(1) })
        let current = marking(planned, [skipped.id], as: .skipped)
        let events = PlanEvents(skipped: [skipped.id], ranOut: [Planning.chicken.id])

        let first = PlanRepairer.repair(current, today: planDay(1), events: events, request: request)
        let second = PlanRepairer.repair(current, today: planDay(1), events: events, request: request)

        #expect(signature(first) == signature(second))
        #expect(first.changes == second.changes)
        #expect(first.result.breakdown == second.result.breakdown)
    }

    @Test func sevenDayRepairIsFast() throws {
        let request = Planning.request(Persona.nutAllergy.constraints, pantry: Planning.pantry.filter { $0.foodID != Planning.chicken.id })
        let planned = WeekPlanner.plan(Planning.request(Persona.nutAllergy.constraints))
        let skipped = try #require(planned.meals.first { $0.date == planDay(2) })
        let current = marking(planned, [skipped.id], as: .skipped)
        let events = PlanEvents(skipped: [skipped.id], ranOut: [Planning.chicken.id])
        let clock = ContinuousClock()

        let elapsed = clock.measure { _ = PlanRepairer.repair(current, today: planDay(1), events: events, request: request) }

        #expect(elapsed < .milliseconds(500))
    }

    @Test func verifierBackstopsAFaultyAdmission() throws {
        let request = Planning.request(
            Persona.nutAllergy.constraints, candidates: [Planning.chickpeaCurry, Planning.romescoChicken], household: 4, days: 2,
            liked: [Planning.chickpeaCurry.recipe.id]
        )
        let planned = WeekPlanner.plan(request)
        let source = try #require(planned.meals.first { $0.leftoverOf == nil })

        let repair = PlanRepairer.repair(
            marking(planned, [source.id], as: .skipped), today: source.date, events: PlanEvents(skipped: [source.id]), request: request
        ) { _ in .admitted(softPenalties: []) }

        #expect(repair.result.verification.hardViolations.isEmpty)
        #expect(!repair.result.meals.contains { $0.recipeID == Planning.romescoChicken.recipe.id })
    }
}
