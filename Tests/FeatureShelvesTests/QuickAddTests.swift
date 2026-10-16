import Foundation
import LarderCore
import Testing

@testable import FeatureShelves

@Suite("Quick add")
struct QuickAddTests {
    private let parsed = [
        ParsedPantryLine(rawText: "2 onions", name: "onions", quantity: 2, unit: .piece),
        ParsedPantryLine(rawText: "milk in the fridge", name: "milk", quantity: 1, unit: .litre, location: .fridge),
        ParsedPantryLine(rawText: "salt", name: "salt"),
    ]

    @Test @MainActor func parsedLinesBecomePendingLinesAndClearTheDraft() async {
        let (model, _, assistant) = Fixture.model(assistant: FakeAssistant(returning: parsed))
        model.quickAddDraft = "2 onions, milk in the fridge, salt"
        await model.quickAdd()
        #expect(model.pendingLines.map(\.name) == ["onions", "milk", "salt"])
        #expect(model.pendingLines[1].location == .fridge)
        #expect(model.pendingLines[1].unit == .litre)
        #expect(model.pendingLines.allSatisfy { $0.source == .naturalLanguage })
        #expect(model.quickAddDraft.isEmpty)
        #expect(model.error == nil)
        #expect(await assistant.receivedTexts == ["2 onions, milk in the fridge, salt"])
    }

    @Test @MainActor func missingQuantityUnitAndLocationGetDefaults() async {
        let (model, _, _) = Fixture.model(assistant: FakeAssistant(returning: parsed))
        model.quickAddDraft = "stuff"
        await model.quickAdd()
        let salt = model.pendingLines[2]
        #expect(salt.quantity == 1)
        #expect(salt.unit == .piece)
        #expect(salt.location == .pantry)
    }

    @Test @MainActor func failureKeepsTheDraftAndSurfacesTheError() async {
        let (model, _, _) = Fixture.model(assistant: FakeAssistant(throwing: .quotaExceeded))
        model.quickAddDraft = "2 onions"
        await model.quickAdd()
        #expect(model.quickAddDraft == "2 onions")
        #expect(model.pendingLines.isEmpty)
        #expect(model.error == .quotaExceeded)
        #expect(!model.isParsing)
    }

    @Test @MainActor func consentRequiredSurfacesAsError() async {
        let (model, _, _) = Fixture.model(assistant: FakeAssistant(throwing: .consentRequired))
        model.quickAddDraft = "2 onions"
        await model.quickAdd()
        #expect(model.error == .consentRequired)
        #expect(model.quickAddDraft == "2 onions")
    }

    @Test @MainActor func blankDraftNeverReachesTheAssistant() async {
        let (model, _, assistant) = Fixture.model(assistant: FakeAssistant(returning: parsed))
        model.quickAddDraft = "  \n "
        await model.quickAdd()
        #expect(await assistant.receivedTexts.isEmpty)
        #expect(model.pendingLines.isEmpty)
        #expect(model.error == nil)
    }

    @Test @MainActor func nothingParsedKeepsTheDraftAndReportsInvalidResponse() async {
        let (model, _, _) = Fixture.model(assistant: FakeAssistant(returning: []))
        model.quickAddDraft = "hmm"
        await model.quickAdd()
        #expect(model.error == .invalidResponse)
        #expect(model.quickAddDraft == "hmm")
    }

    @Test @MainActor func discardPendingClearsLinesAndDraft() async {
        let (model, _, _) = Fixture.model(assistant: FakeAssistant(returning: parsed))
        model.quickAddDraft = "2 onions"
        await model.quickAdd()
        model.quickAddDraft = "more"
        model.discardPending()
        #expect(model.pendingLines.isEmpty)
        #expect(model.quickAddDraft.isEmpty)
    }

    @Test @MainActor func blankLineIsManualAndNotYetConfirmable() {
        let (model, _, _) = Fixture.model()
        model.addBlankLine()
        #expect(model.pendingLines.count == 1)
        #expect(model.pendingLines[0].source == .manual)
        #expect(model.confirmableLines.isEmpty)
    }
}
