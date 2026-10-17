import Foundation
import LarderCore
import Testing

@testable import FeatureShelves

@Suite("Logging what leaves the shelves")
struct PantryEventLogTests {
    @Test @MainActor func eatingLogsTheWholeItemAsEaten() async throws {
        let rice = FoodID()
        let item = Fixture.item("Rice", grams: 750, foodID: rice)
        let (model, pantry, _) = Fixture.model(items: [item])
        await model.load()
        await model.eat(item)
        let event = try #require(await pantry.loggedEvents.first)
        #expect(await pantry.loggedEvents.count == 1)
        #expect(event.kind == .eaten)
        #expect(event.foodID == rice)
        #expect(event.name == "Rice")
        #expect(event.grams == 750)
        #expect(event.date == Fixture.now)
        #expect(event.plannedMealID == nil)
        #expect(model.undo?.eventIDs == [event.id])
    }

    @Test(arguments: [(nil as Int?, PantryEventKind.letGo), (5, .letGo), (0, .letGo), (-1, .expired), (-10, .expired)])
    @MainActor func lettingGoLogsExpiredOncePastItsBestBy(bestByDays: Int?, kind: PantryEventKind) async {
        let item = Fixture.item("Milk", grams: 1_000, location: .fridge, bestByDays: bestByDays)
        let (model, pantry, _) = Fixture.model(items: [item])
        await model.load()
        await model.letGo(item)
        #expect(await pantry.loggedEvents.map(\.kind) == [kind])
    }

    @Test @MainActor func usingSomeLogsTheDifferenceAsEaten() async throws {
        let item = Fixture.item("Rice", grams: 750)
        let (model, pantry, _) = Fixture.model(items: [item])
        await model.load()
        var edited = item
        edited.quantityGrams = 500
        await model.update(edited)
        let event = try #require(await pantry.loggedEvents.first)
        #expect(event.kind == .eaten)
        #expect(event.grams == 250)
        var more = edited
        more.quantityGrams = 900
        await model.update(more)
        #expect(await pantry.loggedEvents.count == 1)
    }

    @Test @MainActor func countedItemsReportTheirPortionAndNumber() async throws {
        let egg = Food(name: "Eggs", source: .seedApproximate, portions: [Portion(label: "egg", grams: 50)], foodGroup: .protein)
        let item = Fixture.item("Eggs", grams: 300, foodID: egg.id)
        let (model, _, _) = Fixture.model(items: [item], foods: [egg])
        await model.load()
        let counted = try #require(model.count(for: item))
        #expect(counted.number == 6)
        #expect(counted.portion.label == "egg")
        #expect(ShelvesCopy.count(5, of: counted.portion) == "5 eggs")
    }

    @Test @MainActor func undoDropsTheLoggedEvent() async {
        let item = Fixture.item("Rice")
        let (model, pantry, _) = Fixture.model(items: [item])
        await model.load()
        await model.letGo(item)
        await model.undoRemove()
        #expect(await pantry.loggedEvents.isEmpty)
        #expect(await pantry.stored == [item])
    }

    @Test @MainActor func undoKeepsEarlierEvents() async {
        let rice = Fixture.item("Rice")
        let beans = Fixture.item("Beans")
        let (model, pantry, _) = Fixture.model(items: [rice, beans])
        await model.load()
        await model.eat(rice)
        await model.eat(beans)
        await model.undoRemove()
        #expect(await pantry.loggedEvents.map(\.name) == ["Rice"])
    }

    @Test @MainActor func eventsReadBackByDateRange() async throws {
        let item = Fixture.item("Rice")
        let (model, pantry, _) = Fixture.model(items: [item])
        await model.load()
        await model.eat(item)
        #expect(try await pantry.events(from: Fixture.date(days: 0, hour: 0), to: Fixture.date(days: 1, hour: 0)).count == 1)
        #expect(try await pantry.events(from: Fixture.date(days: 1, hour: 0), to: Fixture.date(days: 2, hour: 0)).isEmpty)
    }

    @Test @MainActor func aFailedLogStillRemovesTheItemAndOffersUndo() async {
        let item = Fixture.item("Rice")
        let (model, pantry, _) = Fixture.model(items: [item])
        await model.load()
        await pantry.setEventFailure(.storageFailure)
        await model.eat(item)
        #expect(model.items.isEmpty)
        #expect(model.error == .storageFailure)
        #expect(model.undo?.item == item)
        #expect(model.undo?.eventIDs == [])
        await model.undoRemove()
        #expect(await pantry.stored == [item])
    }

    @Test @MainActor func aFailedRemovalLogsNothing() async {
        let item = Fixture.item("Rice")
        let (model, pantry, _) = Fixture.model(items: [item])
        await model.load()
        await pantry.setFailure(.storageFailure)
        await model.eat(item)
        await pantry.setFailure(nil)
        #expect(await pantry.loggedEvents.isEmpty)
        #expect(model.undo == nil)
    }
}
