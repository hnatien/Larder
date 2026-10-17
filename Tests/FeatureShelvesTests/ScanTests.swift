import Foundation
import LarderCore
import Testing

@testable import FeatureShelves

/// Counts receipt reads and answers with fixed lines or an error.
private actor FakeReader {
    private(set) var reads = 0
    private let result: Result<[ParsedPantryLine], any Error>

    init(_ result: Result<[ParsedPantryLine], any Error>) {
        self.result = result
    }

    func read() throws -> [ParsedPantryLine] {
        reads += 1
        return try result.get()
    }
}

private struct ReceiptUnreadable: Error {}

@Suite("Scanning")
struct ScanTests {
    private let oats = Food(name: "Oats", source: .seedApproximate, gtin: "0012345678905", foodGroup: .grains)
    private let milk = Food(name: "Milk, whole", source: .seedApproximate, gtin: "50123452", foodGroup: .dairy, tags: [.dairy])

    @MainActor
    private func model(
        foods: [Food] = [],
        receipt: Result<[ParsedPantryLine], any Error>? = nil,
        barcodes: [String]? = nil,
        isPlus: Bool = true
    ) -> (ShelvesModel, FakeReader?) {
        let reader = receipt.map(FakeReader.init)
        let model = ShelvesModel(
            pantry: FakePantryRepository(),
            foods: FakeFoodRepository(foods: foods),
            assistant: FakeAssistant(),
            dates: FixedDateProvider(Fixture.now),
            calendar: Fixture.calendar,
            receiptReader: reader.map { reader in { @Sendable _ in try await reader.read() } },
            barcodeReader: barcodes.map { codes in { @Sendable _ in codes } },
            isPlus: { isPlus }
        )
        return (model, reader)
    }

    @Test(arguments: [("012345678905", "0012345678905"), ("0012345678905", "0012345678905"), ("00012345678905", "0012345678905"), ("50123452", "50123452")])
    func gtinSpellingsShareOneCanonicalForm(code: String, canonical: String) {
        #expect(GTIN.normalized(code) == canonical)
    }

    @Test(arguments: ["", "12345", "ABCDEFGH", "1234567890", "10012345678905", "0012 345678905"])
    func nonRetailCodesAreRejected(code: String) {
        #expect(GTIN.normalized(code) == nil)
        #expect(GTIN.spellings(of: code).isEmpty)
    }

    @Test func spellingsCoverUPCAndGTIN14() {
        #expect(GTIN.spellings(of: "012345678905") == ["0012345678905", "00012345678905", "012345678905"])
        #expect(GTIN.spellings(of: "5012345678900") == ["5012345678900", "05012345678900"])
    }

    @Test @MainActor func aKnownBarcodeAddsTheFoodWhereItUsuallyLives() async {
        let (model, _) = model(foods: [oats, milk])
        await model.addBarcode("012345678905")
        await model.addBarcode("50123452")
        #expect(model.pendingLines.map(\.name) == ["Oats", "Milk, whole"])
        #expect(model.pendingLines.map(\.location) == [.pantry, .fridge])
        #expect(model.pendingLines.allSatisfy { $0.source == .barcode && $0.quantity == 1 && $0.unit == .piece })
        #expect(model.lastScannedName == "Milk, whole")
        #expect(model.scanNotice == nil)
    }

    @Test @MainActor func aBarcodeTheCameraKeepsSeeingAddsOneLineUntilTheSheetCloses() async {
        let (model, _) = model(foods: [oats])
        await model.addBarcode("012345678905")
        await model.addBarcode("0012345678905")
        #expect(model.pendingLines.count == 1)
        model.discardPending()
        await model.addBarcode("012345678905")
        #expect(model.pendingLines.count == 1)
    }

    @Test @MainActor func anUnknownBarcodeLeavesABlankLineToName() async {
        let (model, _) = model(foods: [oats])
        await model.addBarcode("4006381333931")
        #expect(model.pendingLines.count == 1)
        #expect(model.pendingLines[0].name.isEmpty)
        #expect(model.pendingLines[0].source == .barcode)
        #expect(model.scanNotice == .unknownBarcode)
        #expect(model.confirmableLines.isEmpty)
    }

    @Test @MainActor func textThatIsNotABarcodeIsIgnored() async {
        let (model, _) = model(foods: [oats])
        await model.addBarcode("https://example.com")
        #expect(model.pendingLines.isEmpty)
        #expect(model.scanNotice == nil)
    }

    @Test @MainActor func barcodesInAPhotoEachAddALine() async {
        let (model, _) = model(foods: [oats, milk], barcodes: ["012345678905", "50123452"])
        await model.readBarcodes(inPhoto: Data())
        #expect(model.pendingLines.map(\.name) == ["Oats", "Milk, whole"])
        let (empty, _) = self.model(barcodes: [])
        await empty.readBarcodes(inPhoto: Data())
        #expect(empty.scanNotice == .noBarcode)
    }

    @Test @MainActor func receiptLinesArriveAsReceiptLinesWithTheirBestBy() async {
        let bestBy = Fixture.date(days: 2)
        let (model, reader) = model(receipt: .success([
            ParsedPantryLine(rawText: "chicken", name: "chicken thighs", quantity: 500, unit: .gram, bestBy: bestBy),
            ParsedPantryLine(rawText: "rice", name: "rice"),
            ParsedPantryLine(rawText: "  ", name: "  "),
        ]))
        await model.readReceipt(Data())
        #expect(await reader?.reads == 1)
        #expect(model.pendingLines.map(\.name) == ["chicken thighs", "rice"])
        #expect(model.pendingLines.allSatisfy { $0.source == .receipt })
        #expect(model.pendingLines[0].bestBy == bestBy)
        #expect(model.pendingLines[0].location == .fridge)
        #expect(!model.isParsing)
    }

    @Test @MainActor func freeUsersAreToldReceiptsNeedPlusAndNothingIsRead() async {
        let (model, reader) = model(receipt: .success([ParsedPantryLine(rawText: "rice", name: "rice")]), isPlus: false)
        await model.readReceipt(Data())
        #expect(await reader?.reads == 0)
        #expect(model.scanNotice == .receiptNeedsPlus)
        #expect(model.pendingLines.isEmpty)
    }

    @Test @MainActor func receiptFailuresBecomeNotices() async {
        let (empty, _) = model(receipt: .success([]))
        await empty.readReceipt(Data())
        #expect(empty.scanNotice == .nothingOnReceipt)

        let (blurry, _) = model(receipt: .failure(ReceiptUnreadable()))
        await blurry.readReceipt(Data())
        #expect(blurry.scanNotice == .unreadableReceipt)

        let (offline, _) = model(receipt: .failure(LarderError.quotaExceeded))
        await offline.readReceipt(Data())
        #expect(offline.error == .quotaExceeded)
        #expect(offline.scanNotice == nil)
    }

    @Test @MainActor func withoutReadersTheScannerOffersNeither() {
        let (model, _) = model()
        #expect(!model.canReadReceipts)
        #expect(!model.canReadBarcodePhotos)
    }

    @Test @MainActor func everyNoticeHasCopy() {
        let notices: [ScanNotice] = [.unknownBarcode, .noBarcode, .nothingOnReceipt, .unreadableReceipt, .receiptNeedsPlus]
        #expect(Set(notices.map(ShelvesCopy.message(for:))).count == notices.count)
    }

    @Test @MainActor func parsedBestByCarriesIntoQuickAddLines() async {
        let bestBy = Fixture.date(days: 3)
        let (model, _, _) = Fixture.model(assistant: FakeAssistant(returning: [ParsedPantryLine(rawText: "milk", name: "milk", bestBy: bestBy)]))
        model.quickAddDraft = "milk exp monday"
        await model.quickAdd()
        #expect(model.pendingLines.first?.bestBy == bestBy)
    }
}
