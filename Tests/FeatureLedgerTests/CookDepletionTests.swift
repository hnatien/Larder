import Foundation
import LarderCore
import Testing
@testable import FeatureLedger

@MainActor @Suite struct CookDepletionTests {
    /// Spinach fried rice for 4 from a recipe for 2: rice 600 g, spinach 300 g, eggs 200 g, oil 30 g.
    private func cookedSpinachRice(_ world: World) async -> (LedgerModel, PlannedMeal) {
        let (_, meals) = await world.seed { plan in [Fixtures.meal(Fixtures.spinachRice, in: plan, day: 0, servings: 4)] }
        let model = world.ledger()
        await model.load()
        return (model, meals[0])
    }

    @Test func markCookedTakesTheScaledIngredientsOffTheShelves() async throws {
        let world = World()
        let (model, meal) = await cookedSpinachRice(world)

        await model.markCooked(meal)

        #expect(model.error == nil)
        #expect(model.meals.first?.status == .cooked)
        #expect(await world.plans.meals(for: meal.planID).first?.status == .cooked)
        #expect(await world.pantry.consumed == [
            FoodAmount(foodID: Fixtures.rice.id, grams: 600),
            FoodAmount(foodID: Fixtures.spinach.id, grams: 300),
            FoodAmount(foodID: Fixtures.eggs.id, grams: 200),
            FoodAmount(foodID: Fixtures.oliveOil.id, grams: 30),
        ])
        #expect(await world.pantry.grams(of: Fixtures.rice.id) == 400)
        #expect(await world.pantry.grams(of: Fixtures.spinach.id) == 0)
        #expect(await world.pantry.grams(of: Fixtures.oliveOil.id) == 470)
        #expect(await world.pantry.grams(of: Fixtures.chicken.id) == 600)
        let undo = try #require(model.cookUndo)
        #expect(undo.meal == meal)
        #expect(undo.title == Fixtures.spinachRice.recipe.title)
        #expect(!undo.draw.isEmpty)
    }

    @Test func cookingLogsWhatWasOnTheShelvesForTheMeal() async {
        let world = World()
        let (model, meal) = await cookedSpinachRice(world)

        await model.markCooked(meal)

        let events = await world.pantry.loggedEvents
        // No eggs were on the shelves, so none were logged.
        #expect(events.map(\.foodID) == [Fixtures.rice.id, Fixtures.spinach.id, Fixtures.oliveOil.id])
        #expect(events.map(\.grams) == [600, 300, 30])
        #expect(events.allSatisfy { $0.kind == .cooked && $0.plannedMealID == meal.id && $0.date == Fixtures.now })
        #expect(model.cookUndo?.draw.eventIDs == events.map(\.id))
    }

    @Test func cookingMoreThanIsOnTheShelvesLogsOnlyWhatWasThere() async {
        let world = World()
        let (_, meals) = await world.seed { plan in [Fixtures.meal(Fixtures.spinachRice, in: plan, day: 0, servings: 8)] }
        let model = world.ledger()
        await model.load()

        await model.markCooked(meals[0])

        // 1,200 g of rice asked for, 1,000 g on the shelves.
        #expect(await world.pantry.loggedEvents.first { $0.foodID == Fixtures.rice.id }?.grams == 1_000)
        #expect(await world.pantry.grams(of: Fixtures.rice.id) == 0)
    }

    @Test func aLeftoverIsMarkedCookedWithoutTakingAnything() async throws {
        let world = World()
        let (_, meals) = await world.seed { plan in
            let cooked = Fixtures.meal(Fixtures.chickpeaCurry, in: plan, day: 0, servings: 4)
            return [cooked, Fixtures.meal(Fixtures.chickpeaCurry, in: plan, day: 1, servings: 2, leftoverOf: cooked.id)]
        }
        let model = world.ledger()
        await model.load()

        await model.markCooked(meals[1])

        #expect(model.meals.first { $0.id == meals[1].id }?.status == .cooked)
        #expect(await world.pantry.consumed.isEmpty)
        #expect(await world.pantry.loggedEvents.isEmpty)
        #expect(try #require(model.cookUndo).draw.isEmpty)
    }

    @Test func theMealALeftoverComesFromTakesEveryServingOnce() async {
        let world = World()
        let (_, meals) = await world.seed { plan in
            let cooked = Fixtures.meal(Fixtures.chickpeaCurry, in: plan, day: 0, servings: 4)
            return [cooked, Fixtures.meal(Fixtures.chickpeaCurry, in: plan, day: 1, servings: 2, leftoverOf: cooked.id)]
        }
        let model = world.ledger()
        await model.load()

        await model.markCooked(meals[0])
        await model.markCooked(meals[1])

        // The curry serves 8 and the cooked meal carries the leftover's servings: 800 g * 4/8 = 400 g of chickpeas.
        #expect(await world.pantry.consumed.filter { $0.foodID == Fixtures.chickpeas.id } == [FoodAmount(foodID: Fixtures.chickpeas.id, grams: 400)])
        #expect(await world.pantry.grams(of: Fixtures.chickpeas.id) == 400)
    }

    @Test func markingAMealCookedTwiceTakesItsFoodOnce() async {
        let world = World()
        let (model, meal) = await cookedSpinachRice(world)

        await model.markCooked(meal)
        await model.markCooked(meal)

        #expect(await world.pantry.consumed.count == 4)
        #expect(await world.pantry.grams(of: Fixtures.rice.id) == 400)
    }

    @Test func undoPutsTheShelvesAndTheMealBackAndDropsTheLog() async {
        let world = World()
        let (model, meal) = await cookedSpinachRice(world)
        let before = await world.pantry.items()

        await model.markCooked(meal)
        await model.undoCooked()

        #expect(model.error == nil)
        #expect(model.cookUndo == nil)
        #expect(model.meals.first?.status == .planned)
        #expect(await world.plans.meals(for: meal.planID).first?.status == .planned)
        #expect(Set(await world.pantry.items()) == Set(before))
        #expect(await world.pantry.loggedEvents.isEmpty)
    }

    @Test func aFailurePartWayPutsBackWhatWasTakenAndLeavesTheMealPlanned() async {
        let world = World()
        let (model, meal) = await cookedSpinachRice(world)
        let before = await world.pantry.items()
        await world.pantry.setFailConsume(after: 2)

        await model.markCooked(meal)

        #expect(model.error == .storageFailure)
        #expect(model.meals.first?.status == .planned)
        #expect(model.cookUndo == nil)
        #expect(Set(await world.pantry.items()) == Set(before))
        #expect(await world.pantry.loggedEvents.isEmpty)
    }

    @Test func aFailedLogPutsTheShelvesBack() async {
        let world = World()
        let (model, meal) = await cookedSpinachRice(world)
        let before = await world.pantry.items()
        await world.pantry.setFailEventWrites(true)

        await model.markCooked(meal)

        #expect(model.error == .storageFailure)
        #expect(model.meals.first?.status == .planned)
        #expect(Set(await world.pantry.items()) == Set(before))
    }

    @Test func aFailedStatusSavePutsTheShelvesBack() async {
        let world = World()
        let (model, meal) = await cookedSpinachRice(world)
        let before = await world.pantry.items()
        await world.plans.setFailWrites(true)

        await model.markCooked(meal)

        #expect(model.error == .storageFailure)
        #expect(model.cookUndo == nil)
        #expect(Set(await world.pantry.items()) == Set(before))
        #expect(await world.pantry.loggedEvents.isEmpty)
    }

    @Test func cookingOffPlanScalesToTheServingsCooked() async throws {
        let world = World()
        let model = world.ledger()

        // Spinach omelette for 2 cooked for 1: eggs 150 g, spinach 75 g, parmesan 15 g.
        await model.cookOffPlan(Fixtures.spinachOmelette.recipe, servings: 1)

        #expect(await world.pantry.consumed == [
            FoodAmount(foodID: Fixtures.eggs.id, grams: 150),
            FoodAmount(foodID: Fixtures.spinach.id, grams: 75),
            FoodAmount(foodID: Fixtures.parmesan.id, grams: 15),
        ])
        #expect(await world.pantry.grams(of: Fixtures.spinach.id) == 225)
        #expect(await world.pantry.loggedEvents.map(\.plannedMealID) == [nil])
        let undo = try #require(model.cookUndo)
        #expect(undo.meal == nil)

        await model.undoCooked()
        #expect(await world.pantry.grams(of: Fixtures.spinach.id) == 300)
        #expect(await world.pantry.loggedEvents.isEmpty)
    }

    @Test func dismissingTheUndoLetsTheCookingStand() async {
        let world = World()
        let (model, meal) = await cookedSpinachRice(world)

        await model.markCooked(meal)
        model.dismissCookUndo()
        await model.undoCooked()

        #expect(model.meals.first?.status == .cooked)
        #expect(await world.pantry.grams(of: Fixtures.rice.id) == 400)
    }
}
