import Foundation
import LarderCore
import Testing

@testable import FeatureShelves

@Suite("Eating, letting go, undo and adjusting")
struct RemovalTests {
    @Test @MainActor func eatRemovesTheItemAndOffersUndo() async {
        let rice = Fixture.item("Rice")
        let beans = Fixture.item("Beans")
        let (model, pantry, _) = Fixture.model(items: [rice, beans])
        await model.load()
        await model.eat(rice)
        #expect(model.items == [beans])
        #expect(await pantry.stored == [beans])
        #expect(model.undo?.item == rice)
        #expect(model.undo?.kind == .eaten)
    }

    @Test @MainActor func letGoRemovesTheItemAndOffersUndo() async {
        let rice = Fixture.item("Rice")
        let (model, pantry, _) = Fixture.model(items: [rice])
        await model.load()
        await model.letGo(rice)
        #expect(model.items.isEmpty)
        #expect(await pantry.stored.isEmpty)
        #expect(model.undo?.kind == .letGo)
    }

    @Test @MainActor func undoRestoresTheSameItemID() async {
        let rice = Fixture.item("Rice", grams: 750, location: .pantry, bestByDays: 9)
        let (model, pantry, _) = Fixture.model(items: [rice])
        await model.load()
        await model.eat(rice)
        await model.undoRemove()
        #expect(model.items == [rice])
        #expect(model.items.first?.id == rice.id)
        #expect(await pantry.stored == [rice])
        #expect(model.undo == nil)
    }

    @Test @MainActor func aSecondRemovalReplacesTheUndo() async {
        let rice = Fixture.item("Rice")
        let beans = Fixture.item("Beans")
        let (model, _, _) = Fixture.model(items: [rice, beans])
        await model.load()
        await model.eat(rice)
        await model.letGo(beans)
        #expect(model.undo?.item == beans)
        await model.undoRemove()
        #expect(model.items == [beans])
    }

    @Test @MainActor func undoWithNothingRemovedDoesNothing() async {
        let (model, pantry, _) = Fixture.model(items: [Fixture.item("Rice")])
        await model.load()
        await model.undoRemove()
        #expect(model.items.count == 1)
        #expect(await pantry.stored.count == 1)
    }

    @Test @MainActor func dismissUndoLetsTheRemovalStand() async {
        let rice = Fixture.item("Rice")
        let (model, _, _) = Fixture.model(items: [rice])
        await model.load()
        await model.eat(rice)
        model.dismissUndo()
        await model.undoRemove()
        #expect(model.undo == nil)
        #expect(model.items.isEmpty)
    }

    @Test @MainActor func removalFailureKeepsTheItemAndSetsNoUndo() async {
        let rice = Fixture.item("Rice")
        let (model, pantry, _) = Fixture.model(items: [rice])
        await model.load()
        await pantry.setFailure(.storageFailure)
        await model.eat(rice)
        #expect(model.undo == nil)
        #expect(model.error == .storageFailure)
        #expect(model.items == [rice])
    }

    @Test @MainActor func mutationsReloadFromTheRepository() async {
        let rice = Fixture.item("Rice")
        let (model, pantry, _) = Fixture.model(items: [rice])
        await model.load()
        let arrival = Fixture.item("Arrived elsewhere")
        await pantry.add(arrival)
        await model.eat(rice)
        #expect(model.items == [arrival])
    }

    @Test @MainActor func adjustPersistsTheNewGrams() async {
        let rice = Fixture.item("Rice", grams: 1000)
        let (model, pantry, _) = Fixture.model(items: [rice])
        await model.load()
        await model.adjust(rice, grams: 250)
        #expect(await pantry.stored.first?.quantityGrams == 250)
        #expect(model.items.first?.quantityGrams == 250)
        #expect(model.items.first?.id == rice.id)
    }

    @Test(arguments: [0, -5, Double.nan, Double.infinity])
    @MainActor func adjustIgnoresAmountsThatAreNotPositiveAndFinite(grams: Double) async {
        let rice = Fixture.item("Rice", grams: 1000)
        let (model, pantry, _) = Fixture.model(items: [rice])
        await model.load()
        await model.adjust(rice, grams: grams)
        #expect(await pantry.stored.first?.quantityGrams == 1000)
    }
}
