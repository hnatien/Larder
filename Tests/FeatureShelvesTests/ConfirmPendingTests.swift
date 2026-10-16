import Foundation
import LarderCore
import Testing

@testable import FeatureShelves

@Suite("Confirming pending lines")
struct ConfirmPendingTests {
    @MainActor private func line(
        _ name: String,
        _ quantity: Double,
        _ unit: UnitOfMeasure,
        location: StorageLocation = .pantry,
        source: PantrySource = .naturalLanguage
    ) -> DraftLine {
        DraftLine(name: name, quantity: quantity, unit: unit, location: location, source: source)
    }

    @Test @MainActor func cupsOfRiceBecomeGramsThroughTheFoodDensity() async throws {
        let rice = Fixture.food("Rice, white", density: 0.85)
        let (model, pantry, _) = Fixture.model(foods: [rice])
        model.pendingLines = [line("rice", 2, .cup)]
        let added = await model.confirmPending()
        let saved = try #require(await pantry.stored.first)
        #expect(added == 1)
        #expect(saved.foodID == rice.id)
        #expect(saved.quantityGrams == 2 * 236.59 * 0.85)
        #expect(saved.source == .naturalLanguage)
        #expect(saved.addedOn == Fixture.now)
        #expect(model.items == [saved])
        #expect(model.pendingLines.isEmpty)
    }

    @Test @MainActor func countUnitUsesTheFoodsFirstPortion() async throws {
        let onion = Fixture.food("Onion, raw", portions: [Portion(label: "1 medium", grams: 110)])
        let (model, pantry, _) = Fixture.model(foods: [onion])
        model.pendingLines = [line("onions", 3, .piece)]
        await model.confirmPending()
        #expect(try #require(await pantry.stored.first).quantityGrams == 330)
    }

    @Test @MainActor func noMatchingFoodStoresTheRawQuantity() async throws {
        let (model, pantry, _) = Fixture.model(foods: [Fixture.food("Rice, white", density: 0.85)])
        model.pendingLines = [line("dragon fruit", 2, .cup)]
        await model.confirmPending()
        let saved = try #require(await pantry.stored.first)
        #expect(saved.foodID == nil)
        #expect(saved.quantityGrams == 2)
        #expect(saved.rawName == "dragon fruit")
    }

    @Test @MainActor func topHitWithADifferentFirstWordIsRejected() async throws {
        let bread = Fixture.food("Bread, white", portions: [Portion(label: "1 slice", grams: 30)])
        let (model, pantry, _) = Fixture.model(foods: [bread])
        model.pendingLines = [line("sourdough bread", 4, .slice)]
        await model.confirmPending()
        let saved = try #require(await pantry.stored.first)
        #expect(saved.foodID == nil)
        #expect(saved.quantityGrams == 4)
    }

    @Test @MainActor func massUnitsConvertWithoutAFood() async throws {
        let (model, pantry, _) = Fixture.model()
        model.pendingLines = [line("flour", 2, .kilogram)]
        await model.confirmPending()
        #expect(try #require(await pantry.stored.first).quantityGrams == 2000)
    }

    @Test @MainActor func lineLocationAndBestByAreKept() async throws {
        let bestBy = Fixture.date(days: 5)
        let (model, pantry, _) = Fixture.model()
        var milk = line("milk", 1, .litre, location: .fridge)
        milk.bestBy = bestBy
        model.pendingLines = [milk]
        await model.confirmPending()
        let saved = try #require(await pantry.stored.first)
        #expect(saved.location == .fridge)
        #expect(saved.bestBy == bestBy)
    }

    @Test @MainActor func handTypedLinesKeepTheManualSource() async throws {
        let (model, pantry, _) = Fixture.model()
        model.pendingLines = [line("oats", 500, .gram, source: .manual)]
        await model.confirmPending()
        #expect(try #require(await pantry.stored.first).source == .manual)
    }

    @Test @MainActor func invalidLinesAreSkippedAndNotCounted() async {
        let (model, pantry, _) = Fixture.model()
        model.pendingLines = [
            line("oats", 500, .gram),
            line("  ", 1, .piece),
            line("ghost", 0, .piece),
            line("negative", -2, .gram),
            line("nan", .nan, .gram),
        ]
        let added = await model.confirmPending()
        #expect(added == 1)
        #expect(await pantry.stored.map(\.rawName) == ["oats"])
        #expect(model.pendingLines.isEmpty)
    }

    @Test @MainActor func saveFailureKeepsTheLinesAndSurfacesTheError() async {
        let (model, pantry, _) = Fixture.model()
        await pantry.setFailure(.storageFailure)
        model.pendingLines = [line("oats", 500, .gram), line("rice", 1, .kilogram)]
        let added = await model.confirmPending()
        #expect(added == 0)
        #expect(model.pendingLines.map(\.name) == ["oats", "rice"])
        #expect(model.error == .storageFailure)
    }

    @Test @MainActor func foodSearchFailureKeepsTheLines() async {
        let pantry = FakePantryRepository()
        let foods = FakeFoodRepository()
        await foods.setFailure(.storageFailure)
        let model = ShelvesModel(
            pantry: pantry,
            foods: foods,
            assistant: FakeAssistant(),
            dates: FixedDateProvider(Fixture.now),
            calendar: Fixture.calendar
        )
        model.pendingLines = [line("oats", 500, .gram)]
        await model.confirmPending()
        #expect(model.pendingLines.count == 1)
        #expect(model.error == .storageFailure)
        #expect(await pantry.stored.isEmpty)
    }

    @Test @MainActor func addManualSavesOneManualItem() async throws {
        let (model, pantry, _) = Fixture.model()
        await model.addManual(line("tea", 80, .gram, source: .naturalLanguage))
        let saved = try #require(await pantry.stored.first)
        #expect(saved.source == .manual)
        #expect(saved.quantityGrams == 80)
        #expect(model.items == [saved])
    }

    @Test @MainActor func addManualIgnoresAnInvalidLine() async {
        let (model, pantry, _) = Fixture.model()
        await model.addManual(DraftLine())
        #expect(await pantry.stored.isEmpty)
        #expect(model.error == nil)
    }
}
