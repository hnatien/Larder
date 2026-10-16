import Foundation
import LarderCore
import Testing

@testable import FeatureShelves

@MainActor
@Suite("Pantry lists, search, editing and amounts")
struct PantryRedesignTests {
    @Test func useSoonItemsAreNotRepeatedUnderTheirLocation() async {
        let model = await Fixture.loadedModel(items: [
            Fixture.item("Spinach", location: .fridge, bestByDays: 1),
            Fixture.item("Milk", location: .fridge, bestByDays: 10),
        ])
        #expect(model.eatFirst.map(\.rawName) == ["Spinach"])
        #expect(model.shelves.map(\.0) == [.fridge])
        #expect(model.shelves.first?.1.map(\.rawName) == ["Milk"])
    }

    @Test func searchNarrowsBothListsIgnoringCase() async {
        let model = await Fixture.loadedModel(items: [
            Fixture.item("Spinach", location: .fridge, bestByDays: 1),
            Fixture.item("Rice", location: .pantry),
            Fixture.item("Brown rice", location: .pantry),
        ])
        model.searchText = "RICE"
        #expect(model.eatFirst.isEmpty)
        #expect(model.shelves.first?.1.map(\.rawName) == ["Brown rice", "Rice"])
        model.searchText = "  "
        #expect(model.eatFirst.count == 1)
    }

    @Test func updateSavesTrimmedEditsAndIgnoresInvalidOnes() async throws {
        let item = Fixture.item("Rice", grams: 500)
        let (model, pantry, _) = Fixture.model(items: [item])
        await model.load()
        var edited = item
        edited.rawName = "  Basmati rice "
        edited.quantityGrams = 250
        edited.location = .other
        await model.update(edited)
        #expect(model.items.first?.rawName == "Basmati rice")
        #expect(model.items.first?.quantityGrams == 250)
        #expect(model.items.first?.location == .other)

        var blank = edited
        blank.rawName = " "
        await model.update(blank)
        var empty = edited
        empty.quantityGrams = 0
        await model.update(empty)
        #expect(try await pantry.items().first?.rawName == "Basmati rice")
        #expect(try await pantry.items().first?.quantityGrams == 250)
    }

    @Test func staplesToggleOnAndOffThePendingLines() {
        let (model, _, _) = Fixture.model()
        let eggs = ShelvesCopy.staples[0]
        model.toggle(eggs)
        #expect(model.isPending(eggs))
        #expect(model.pendingLines.map(\.name) == [eggs.name])
        #expect(model.pendingLines.first?.location == eggs.location)
        model.toggle(eggs)
        #expect(!model.isPending(eggs))
        #expect(model.pendingLines.isEmpty)
    }

    @Test func countablePortionsReadAsPieces() {
        let egg = [Portion(label: "egg", grams: 50)]
        #expect(ShelvesCopy.quantity(grams: 300, portions: egg) == "6 eggs")
        #expect(ShelvesCopy.quantity(grams: 50, portions: egg) == "1 egg")
        let onion = [Portion(label: "medium onion", grams: 110), Portion(label: "cup chopped", grams: 160)]
        #expect(ShelvesCopy.quantity(grams: 330, portions: onion) == "3 medium onions")
        let chickpeas = [Portion(label: "can drained", grams: 240), Portion(label: "cup", grams: 164)]
        #expect(ShelvesCopy.quantity(grams: 480, portions: chickpeas) == "2 cans drained")
        let garlic = [Portion(label: "clove", grams: 3), Portion(label: "bulb", grams: 40)]
        #expect(ShelvesCopy.quantity(grams: 40, portions: garlic) == "1 bulb")
    }

    @Test func measuringPortionsAndUnevenAmountsFallBackToWeight() {
        let rice = [Portion(label: "cup dry", grams: 185), Portion(label: "serving dry", grams: 75)]
        #expect(ShelvesCopy.quantity(grams: 400, portions: rice, locale: Locale(identifier: "en_US")) == "400 g")
        let egg = [Portion(label: "egg", grams: 50)]
        #expect(ShelvesCopy.quantity(grams: 75, portions: egg, locale: Locale(identifier: "en_US")) == "75 g")
        #expect(ShelvesCopy.quantity(grams: 200, portions: [], locale: Locale(identifier: "en_US")) == "200 g")
    }

    @Test func pluralsFollowTheNoun() {
        #expect(ShelvesCopy.plural("dish") == "dishes")
        #expect(ShelvesCopy.plural("berry") == "berries")
        #expect(ShelvesCopy.plural("tbsp juice") == "tbsps juice")
    }
}
