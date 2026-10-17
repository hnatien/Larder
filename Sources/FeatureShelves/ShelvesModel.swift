import Foundation
import LarderCore
import LarderDesign
import Observation

/// Something a scan found that the Add food sheet tells the user about.
public enum ScanNotice: Hashable, Sendable {
    /// A barcode that matches no food in Larder; a blank line waits for its name.
    case unknownBarcode
    /// A photo with no barcode Larder could read.
    case noBarcode
    /// A receipt with no food lines on it.
    case nothingOnReceipt
    /// A receipt photo that could not be read at all.
    case unreadableReceipt
    /// A free user tried a receipt; reading receipts is a Larder Plus feature.
    case receiptNeedsPlus
}

/// Drives the shelves screen; every mutation reloads from the repository so the UI shows persisted truth.
@Observable
@MainActor
public final class ShelvesModel {
    /// Items this many days from their best-by date, or fewer, belong on the Eat first shelf.
    static let soonDays = 3

    public private(set) var items: [PantryItem] = []
    public private(set) var foodsByID: [FoodID: Food] = [:]
    public private(set) var isLoading = false
    public private(set) var isParsing = false
    public private(set) var error: LarderError?
    public private(set) var undo: UndoAction?
    public var quickAddDraft = ""
    public var pendingLines: [DraftLine] = []
    /// Narrows the lists to items whose name contains this text; empty shows everything.
    public var searchText = ""
    /// What the last scan found that needs saying, such as a barcode Larder does not know.
    public private(set) var scanNotice: ScanNotice?
    /// The food the last scanned barcode matched, for announcing it.
    public private(set) var lastScannedName: String?

    private let pantry: any PantryRepository
    private let foods: any FoodRepository
    private let assistant: any AssistantBackend
    private let dates: any DateProvider
    private let calendar: Calendar
    private let receiptReader: (@Sendable (Data) async throws -> [ParsedPantryLine])?
    private let barcodeReader: (@Sendable (Data) async throws -> [String])?
    private let isPlus: @Sendable () async -> Bool
    /// Barcodes already turned into lines since the sheet opened, so a code the camera keeps seeing adds one line.
    private var scannedBarcodes: Set<String> = []

    /// Creates a model over the given ports; `calendar` decides which instants count as the same day.
    ///
    /// `receiptReader` turns a receipt photo into lines (a Plus feature, checked with `isPlus`) and `barcodeReader`
    /// finds the barcodes in a photo; without them the scanner offers neither.
    public init(
        pantry: any PantryRepository,
        foods: any FoodRepository,
        assistant: any AssistantBackend,
        dates: any DateProvider,
        calendar: Calendar = .current,
        receiptReader: (@Sendable (Data) async throws -> [ParsedPantryLine])? = nil,
        barcodeReader: (@Sendable (Data) async throws -> [String])? = nil,
        isPlus: @escaping @Sendable () async -> Bool = { false }
    ) {
        self.pantry = pantry
        self.foods = foods
        self.assistant = assistant
        self.dates = dates
        self.calendar = calendar
        self.receiptReader = receiptReader
        self.barcodeReader = barcodeReader
        self.isPlus = isPlus
    }

    /// Whether receipt photos can be read on this build.
    public var canReadReceipts: Bool { receiptReader != nil }

    /// Whether barcodes can be read from a still photo on this build.
    public var canReadBarcodePhotos: Bool { barcodeReader != nil }

    /// The current moment, for defaulting a best-by date.
    public var now: Date { dates.now }

    /// Items matching `searchText`.
    var visibleItems: [PantryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { $0.rawName.localizedStandardContains(query) }
    }

    /// Items best by within three days or already past, soonest first.
    public var eatFirst: [PantryItem] {
        visibleItems
            .filter { freshness(for: $0) != .fresh }
            .sorted { ($0.bestBy ?? .distantFuture, $0.rawName) < ($1.bestBy ?? .distantFuture, $1.rawName) }
    }

    /// Non-empty storage locations in shelf order, each sorted by name. Items on the Use soon list show there only.
    public var shelves: [(StorageLocation, [PantryItem])] {
        StorageLocation.allCases.compactMap { location in
            let kept = visibleItems
                .filter { $0.location == location && freshness(for: $0) == .fresh }
                .sorted { $0.rawName.localizedStandardCompare($1.rawName) == .orderedAscending }
            return kept.isEmpty ? nil : (location, kept)
        }
    }

    /// Pending lines that have a name and a positive quantity.
    public var confirmableLines: [DraftLine] { pendingLines.filter(\.isValid) }

    /// How fresh an item is today; an item with no best-by date is fresh.
    public func freshness(for item: PantryItem) -> FreshnessStyle.Level {
        guard let bestBy = item.bestBy else { return .fresh }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: dates.now), to: calendar.startOfDay(for: bestBy)
        ).day ?? 0
        switch days {
        case ..<0: return .past
        case 0: return .today
        case 1...Self.soonDays: return .soon
        default: return .fresh
        }
    }

    /// Loads the shelves from the repository.
    public func load() async {
        error = nil
        isLoading = true
        defer { isLoading = false }
        await reload()
    }

    /// Parses the draft into pending lines; the draft stays when parsing fails or finds nothing.
    public func quickAdd() async {
        let text = quickAddDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        error = nil
        isParsing = true
        defer { isParsing = false }
        do {
            let parsed = try await assistant.parsePantry(text: text)
            guard !parsed.isEmpty else {
                error = .invalidResponse
                return
            }
            pendingLines += await drafts(from: parsed, source: .naturalLanguage)
            quickAddDraft = ""
        } catch {
            record(error, fallback: .assistantUnavailable)
        }
    }

    /// Pending lines for parsed lines, each kept where that food usually lives unless the text said otherwise.
    private func drafts(from parsed: [ParsedPantryLine], source: PantrySource) async -> [DraftLine] {
        var drafts: [DraftLine] = []
        for line in parsed {
            var draft = DraftLine(parsed: line, source: source)
            if line.location == nil {
                // The catalogue only sharpens the guess, so a failed lookup falls back to the name alone.
                let food = try? await matchingFood(for: line.name)
                draft.location = .usual(forItemNamed: line.name, food: food)
            }
            drafts.append(draft)
        }
        return drafts
    }

    // MARK: Scanning

    /// Adds a pending line for a scanned barcode: the matching food, or a blank line to name when no food has it.
    /// A barcode already scanned since the sheet opened is ignored, as is anything that is not a retail barcode.
    public func addBarcode(_ code: String) async {
        guard let gtin = GTIN.normalized(code), !scannedBarcodes.contains(gtin) else { return }
        scannedBarcodes.insert(gtin)
        error = nil
        scanNotice = nil
        let food: Food?
        do {
            food = try await foods.food(byGTIN: gtin)
        } catch {
            scannedBarcodes.remove(gtin)
            record(error, fallback: .storageFailure)
            return
        }
        guard let food else {
            pendingLines.append(DraftLine(source: .barcode))
            scanNotice = .unknownBarcode
            return
        }
        pendingLines.append(DraftLine(name: food.name, location: .usual(forItemNamed: food.name, food: food), source: .barcode))
        lastScannedName = food.name
    }

    /// Adds a line for each barcode in a still photo.
    public func readBarcodes(inPhoto data: Data) async {
        guard let barcodeReader else { return }
        error = nil
        scanNotice = nil
        isParsing = true
        defer { isParsing = false }
        let codes: [String]
        do {
            codes = try await barcodeReader(data)
        } catch is CancellationError {
            return
        } catch {
            scanNotice = .noBarcode
            return
        }
        guard !codes.isEmpty else {
            scanNotice = .noBarcode
            return
        }
        for code in codes { await addBarcode(code) }
    }

    /// Reads a receipt photo into pending lines; a Plus feature, so a free user is told so and nothing is read.
    public func readReceipt(_ data: Data) async {
        guard let receiptReader else { return }
        guard await isPlus() else {
            scanNotice = .receiptNeedsPlus
            return
        }
        error = nil
        scanNotice = nil
        isParsing = true
        defer { isParsing = false }
        do {
            let parsed = try await receiptReader(data).filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !parsed.isEmpty else {
                scanNotice = .nothingOnReceipt
                return
            }
            pendingLines += await drafts(from: parsed, source: .receipt)
        } catch let failure as LarderError {
            record(failure, fallback: .assistantUnavailable)
        } catch is CancellationError {
            return
        } catch {
            scanNotice = .unreadableReceipt
        }
    }

    /// Clears the scan notice once the sheet has shown it.
    public func clearScanNotice() {
        scanNotice = nil
    }

    /// Whether a pending line already carries this staple.
    public func isPending(_ staple: Staple) -> Bool {
        pendingLines.contains { $0.name.caseInsensitiveCompare(staple.name) == .orderedSame }
    }

    /// Adds the staple as a pending line, or takes it back off when it is already pending.
    public func toggle(_ staple: Staple) {
        if isPending(staple) {
            pendingLines.removeAll { $0.name.caseInsensitiveCompare(staple.name) == .orderedSame }
        } else {
            pendingLines.append(staple.line)
        }
    }

    /// Appends a blank line for typing an item by hand.
    public func addBlankLine() {
        pendingLines.append(DraftLine())
    }

    /// Drops the pending lines, the draft and what was scanned.
    public func discardPending() {
        pendingLines = []
        quickAddDraft = ""
        scannedBarcodes = []
        scanNotice = nil
        lastScannedName = nil
    }

    /// Saves every valid pending line and returns how many were added; lines that fail to save stay pending.
    @discardableResult
    public func confirmPending() async -> Int {
        error = nil
        var added = 0
        for line in confirmableLines {
            do {
                try await save(line, source: line.source)
            } catch {
                record(error, fallback: .storageFailure)
                break
            }
            pendingLines.removeAll { $0.id == line.id }
            added += 1
        }
        if error == nil { pendingLines = [] }
        await reload()
        return added
    }

    /// Saves one line as a manual entry.
    public func addManual(_ line: DraftLine) async {
        guard line.isValid else { return }
        do {
            try await save(line, source: .manual)
        } catch {
            record(error, fallback: .storageFailure)
        }
        await reload()
    }

    /// Removes an item that was eaten, keeping an undo on offer.
    public func eat(_ item: PantryItem) async {
        await remove(item, kind: .eaten)
    }

    /// Removes an item that went unused, keeping an undo on offer.
    public func letGo(_ item: PantryItem) async {
        await remove(item, kind: .letGo)
    }

    /// Sets the quantity of an item; ignores amounts that are not positive and finite, since removing is `eat` or `letGo`.
    public func adjust(_ item: PantryItem, grams: Double) async {
        guard grams.isFinite, grams > 0 else { return }
        var adjusted = item
        adjusted.quantityGrams = grams
        do {
            try await pantry.upsert(adjusted)
        } catch {
            record(error, fallback: .storageFailure)
        }
        await reload()
    }

    /// Saves an edited item; a blank name or an amount that is not positive and finite is ignored.
    public func update(_ item: PantryItem) async {
        var edited = item
        edited.rawName = item.rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !edited.rawName.isEmpty, edited.quantityGrams.isFinite, edited.quantityGrams > 0 else { return }
        error = nil
        do {
            try await pantry.upsert(edited)
        } catch {
            record(error, fallback: .storageFailure)
        }
        await reload()
    }

    /// The amount of an item in words, counting pieces when its food has a countable portion.
    public func quantityText(for item: PantryItem) -> String {
        ShelvesCopy.quantity(grams: item.quantityGrams, portions: item.foodID.flatMap { foodsByID[$0] }?.portions ?? [])
    }

    /// Puts the last removed item back on the shelves.
    public func undoRemove() async {
        guard let action = undo else { return }
        undo = nil
        do {
            try await pantry.upsert(action.item)
        } catch {
            record(error, fallback: .storageFailure)
        }
        await reload()
    }

    /// Lets the last removal stand.
    public func dismissUndo() {
        undo = nil
    }

    /// Clears the current error.
    public func clearError() {
        error = nil
    }

    private func remove(_ item: PantryItem, kind: UndoAction.Kind) async {
        do {
            try await pantry.remove(item.id)
            undo = UndoAction(item: item, kind: kind)
        } catch {
            record(error, fallback: .storageFailure)
        }
        await reload()
    }

    private func reload() async {
        do {
            let loaded = try await pantry.items()
            let foodIDs = Array(Set(loaded.compactMap(\.foodID)))
            let known = try await foods.foods(byIDs: foodIDs)
            items = loaded
            foodsByID = Dictionary(known.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        } catch {
            record(error, fallback: .storageFailure)
        }
    }

    private func save(_ line: DraftLine, source: PantrySource) async throws {
        let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let food = try await matchingFood(for: name)
        // A quantity that cannot become grams (a count with no portion, a volume with no density) is stored as entered.
        let grams = (try? UnitConverter.grams(
            from: line.quantity, unit: line.unit, density: food?.densityGPerMl, portion: food?.portions.first
        )) ?? line.quantity
        try await pantry.upsert(
            PantryItem(
                foodID: food?.id,
                rawName: name,
                quantityGrams: grams,
                location: line.location,
                bestBy: line.bestBy,
                source: source,
                addedOn: dates.now
            )
        )
    }

    /// The top search hit, accepted only when its name starts with the same word as `name`, ignoring case and a plural s.
    private func matchingFood(for name: String) async throws -> Food? {
        guard let word = Self.firstWord(of: name),
            let hit = try await foods.search(text: name, limit: 1).first,
            Self.firstWord(of: hit.name) == word
        else { return nil }
        return hit
    }

    /// The first word, lowercased, with a plural "s" dropped so "onions" meets "Onion, raw".
    private static func firstWord(of text: String) -> String? {
        text.split(whereSeparator: { !$0.isLetter }).first.map { word in
            let lowered = word.lowercased()
            return lowered.count > 3 && lowered.hasSuffix("s") ? String(lowered.dropLast()) : lowered
        }
    }

    private func record(_ failure: any Error, fallback: LarderError) {
        guard !(failure is CancellationError) else { return }
        error = failure as? LarderError ?? fallback
    }
}
