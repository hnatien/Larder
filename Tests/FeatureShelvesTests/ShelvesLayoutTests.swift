import Foundation
import LarderCore
import Testing

@testable import FeatureShelves

@Suite("Shelves layout and loading")
struct ShelvesLayoutTests {
    @Test @MainActor func shelvesFollowFridgeFreezerPantryOther() async {
        let model = await Fixture.loadedModel(items: [
            Fixture.item("Salt", location: .other),
            Fixture.item("Rice", location: .pantry),
            Fixture.item("Peas", location: .freezer),
            Fixture.item("Milk", location: .fridge),
        ])
        #expect(model.shelves.map(\.0) == [.fridge, .freezer, .pantry, .other])
    }

    @Test @MainActor func shelvesOmitEmptyLocations() async {
        let model = await Fixture.loadedModel(items: [Fixture.item("Rice", location: .pantry)])
        #expect(model.shelves.map(\.0) == [.pantry])
    }

    @Test @MainActor func itemsWithinAShelfSortByName() async {
        let model = await Fixture.loadedModel(items: [
            Fixture.item("Rice", location: .pantry),
            Fixture.item("Beans", location: .pantry),
            Fixture.item("Oats", location: .pantry),
        ])
        #expect(model.shelves.first?.1.map(\.rawName) == ["Beans", "Oats", "Rice"])
    }

    @Test @MainActor func loadFillsItemsAndFoodsByID() async {
        let rice = Fixture.food("Rice, white")
        let model = await Fixture.loadedModel(
            items: [Fixture.item("Rice", foodID: rice.id), Fixture.item("Mystery jar")],
            foods: [rice]
        )
        #expect(model.items.count == 2)
        #expect(model.foodsByID == [rice.id: rice])
        #expect(!model.isLoading)
        #expect(model.error == nil)
    }

    @Test @MainActor func loadFailureSetsErrorAndStopsLoading() async {
        let (model, pantry, _) = Fixture.model(items: [Fixture.item("Rice")])
        await pantry.setFailure(.storageFailure)
        await model.load()
        #expect(model.error == .storageFailure)
        #expect(!model.isLoading)
        #expect(model.items.isEmpty)
    }

    @Test @MainActor func loadClearsAnEarlierError() async {
        let (model, pantry, _) = Fixture.model(items: [Fixture.item("Rice")])
        await pantry.setFailure(.storageFailure)
        await model.load()
        await pantry.setFailure(nil)
        await model.load()
        #expect(model.error == nil)
        #expect(model.items.count == 1)
    }

    @Test @MainActor func clearErrorResetsError() async {
        let (model, pantry, _) = Fixture.model()
        await pantry.setFailure(.storageFailure)
        await model.load()
        model.clearError()
        #expect(model.error == nil)
    }

    @Test @MainActor func quantityStampReadsInGrams() {
        #expect(ShelvesCopy.quantity(grams: 500, locale: Locale(identifier: "en_US")) == "500 g")
    }
}
