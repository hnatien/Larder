import Foundation
import Synchronization
import Testing
import LarderCore
@testable import LarderOnDeviceAI

enum ReceiptFixtures {
    static let grocery = [
        "GREEN GROCER MARKET",
        "12 High Street, Springfield",
        "Tel 01234 567890",
        "16/10/2026 14:32",
        "Whole Milk 2L        1.45",
        "Free Range Eggs x6   2.10",
        "Basmati Rice 1kg     £1.89",
        "Cheddar 400g         3.25 A",
        "Bananas              0.89",
        "SUBTOTAL             9.58",
        "TOTAL                £9.58",
        "VISA                 9.58",
        "Thank you for shopping",
    ]

    static let loyaltyCard = [
        "FRESHWAY",
        "Store 0412",
        "Oat Milk             1.80",
        "Clubcard Price      -0.30",
        "Sourdough Loaf       2.50",
        "Loyalty card ************4821",
        "Points earned 12",
        "Greek Yogurt 500g    2.20",
        "TOTAL                6.20",
        "MASTERCARD           6.20",
        "CARD NUMBER 5412 7512 3412 3456",
    ]

    static let weights = [
        "CORNER MARKET",
        "Carrots loose",
        "0.512 kg @ 2.99/kg   1.53",
        "Apples 1.204 kg @ 1.50/kg 1.81",
        "Tomatoes 6 @ 0.25    1.50",
        "Butter 250g          1.99",
        "BALANCE DUE          6.83",
        "CASH                10.00",
        "CHANGE               3.17",
    ]
}

struct ReceiptLineFilterTests {
    @Test func groceryReceiptKeepsProductsWithoutPricesHeaderOrFooter() {
        #expect(ReceiptLineFilter.pantryCandidates(from: ReceiptFixtures.grocery) == [
            "Whole Milk 2L", "Free Range Eggs x6", "Basmati Rice 1kg", "Cheddar 400g", "Bananas",
        ])
    }

    @Test func loyaltyCardAndSavingLinesAreDropped() {
        #expect(ReceiptLineFilter.pantryCandidates(from: ReceiptFixtures.loyaltyCard) == [
            "Oat Milk", "Sourdough Loaf", "Greek Yogurt 500g",
        ])
    }

    @Test func weightsStayWithTheirProductAndUnitPricesAreRemoved() {
        #expect(ReceiptLineFilter.pantryCandidates(from: ReceiptFixtures.weights) == [
            "Carrots loose 0.512 kg", "Apples 1.204 kg", "Tomatoes 6", "Butter 250g",
        ])
    }

    @Test func listsWithoutPricesKeepEveryLineWithEnoughLetters() {
        #expect(ReceiptLineFilter.pantryCandidates(from: ["Leeks", " spinach ", "", "2x", "Oats"]) == ["Leeks", "spinach", "Oats"])
        #expect(ReceiptLineFilter.pantryCandidates(from: []) == [])
    }

    @Test func datesTimesCardNumbersAndCurrencyLinesAreDropped() {
        let lines = [
            "Pasta 500g 0.95",
            "2026-10-16 receipt copy",
            "Paid at 09:41",
            "4111 1111 1111 1111",
            "4111111111111111",
            "Gift voucher €5 off",
            "XXXX1234 approved",
            "Rice 1.10",
        ]
        #expect(ReceiptLineFilter.pantryCandidates(from: lines) == ["Pasta 500g", "Rice"])
    }

    @Test func aWeightLineBeforeAnyProductIsDropped() {
        #expect(ReceiptLineFilter.pantryCandidates(from: ["0.300 kg @ 4.00/kg 1.20", "Leeks 0.80"]) == ["Leeks"])
    }
}

struct ReadingOrderTests {
    @Test func fragmentsOnOneRowJoinLeftToRightAndRowsRunTopToBottom() {
        let fragments = [
            TextFragment(text: "1.45", minX: 0.8, midY: 0.795, height: 0.04),
            TextFragment(text: "Bananas", minX: 0.1, midY: 0.70, height: 0.04),
            TextFragment(text: "Whole Milk", minX: 0.1, midY: 0.80, height: 0.04),
            TextFragment(text: "0.89", minX: 0.8, midY: 0.71, height: 0.04),
        ]
        #expect(ReadingOrder.lines(from: fragments) == ["Whole Milk 1.45", "Bananas 0.89"])
    }

    @Test func blankFragmentsAreDroppedAndTextIsTrimmed() {
        let fragments = [
            TextFragment(text: "  ", minX: 0.1, midY: 0.9, height: 0.04),
            TextFragment(text: " Leeks ", minX: 0.1, midY: 0.5, height: 0.04),
        ]
        #expect(ReadingOrder.lines(from: fragments) == ["Leeks"])
        #expect(ReadingOrder.lines(from: []) == [])
    }
}

/// An assistant double that records the pantry text it receives.
final class RecordingAssistant: AssistantBackend {
    private let texts = Mutex<[String]>([])
    private let failure: LarderError?

    init(failure: LarderError? = nil) {
        self.failure = failure
    }

    var receivedTexts: [String] { texts.withLock { $0 } }

    func explain(plan: PlanExplainRequest) async throws -> PlanExplanation {
        throw LarderError.assistantUnavailable
    }

    func parsePantry(text: String) async throws -> [ParsedPantryLine] {
        texts.withLock { $0.append(text) }
        if let failure { throw failure }
        return [ParsedPantryLine(rawText: text, name: "parsed")]
    }

    func parseRecipe(text: String, imageData: Data?) async throws -> ParsedRecipe {
        throw LarderError.assistantUnavailable
    }

    func adjust(request: AdjustRequest) async throws -> ConstraintEdit {
        throw LarderError.assistantUnavailable
    }
}

struct ReceiptToPantryTests {
    @Test func candidatesAreJoinedWithCommasAndParsedOnce() async throws {
        let assistant = RecordingAssistant()
        let lines = try await ReceiptToPantry.parse(lines: ReceiptFixtures.loyaltyCard, assistant: assistant)
        #expect(assistant.receivedTexts == ["Oat Milk, Sourdough Loaf, Greek Yogurt 500g"])
        #expect(lines.map(\.name) == ["parsed"])
    }

    @Test func receiptsWithNoCandidatesNeverReachTheAssistant() async throws {
        let assistant = RecordingAssistant()
        let lines = try await ReceiptToPantry.parse(lines: ["TOTAL 9.58", "VISA 9.58"], assistant: assistant)
        #expect(lines.isEmpty)
        #expect(assistant.receivedTexts.isEmpty)
    }

    @Test func assistantErrorsPropagate() async {
        let assistant = RecordingAssistant(failure: .quotaExceeded)
        await #expect(throws: LarderError.quotaExceeded) {
            try await ReceiptToPantry.parse(lines: ReceiptFixtures.grocery, assistant: assistant)
        }
    }

    @Test func unreadablePhotosFailBeforeTheAssistant() async {
        let assistant = RecordingAssistant()
        await #expect(throws: ImageScanError.unreadableImage) {
            try await ReceiptToPantry.parse(imageData: Data("not an image".utf8), assistant: assistant)
        }
        #expect(assistant.receivedTexts.isEmpty)
    }
}
