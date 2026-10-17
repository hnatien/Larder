#if DEBUG
import Foundation
import LarderCore

/// An in-memory pantry for previews and tests; set `failure` to make every call throw.
actor FakePantryRepository: PantryRepository {
    private(set) var stored: [PantryItem]
    /// Events written with `record(_:)`, in the order they were written.
    private(set) var loggedEvents: [PantryEvent] = []
    var failure: LarderError?
    /// Makes only `record(_:)` throw.
    var eventFailure: LarderError?

    init(items: [PantryItem] = []) {
        self.stored = items
    }

    func setFailure(_ failure: LarderError?) {
        self.failure = failure
    }

    func setEventFailure(_ failure: LarderError?) {
        eventFailure = failure
    }

    func add(_ item: PantryItem) {
        stored.append(item)
    }

    func items() throws -> [PantryItem] {
        try failIfNeeded()
        return stored
    }

    func upsert(_ item: PantryItem) throws {
        try failIfNeeded()
        if let index = stored.firstIndex(where: { $0.id == item.id }) {
            stored[index] = item
        } else {
            stored.append(item)
        }
    }

    func remove(_ id: PantryItemID) throws {
        try failIfNeeded()
        stored.removeAll { $0.id == id }
    }

    func consume(foodID: FoodID, grams: Double) throws -> [PantryItem] {
        try failIfNeeded()
        var remaining = grams
        var touched: [PantryItem] = []
        let order = stored.indices
            .filter { stored[$0].foodID == foodID }
            .sorted { (stored[$0].bestBy ?? .distantFuture) < (stored[$1].bestBy ?? .distantFuture) }
        for index in order where remaining > 0 {
            touched.append(stored[index])
            let taken = min(remaining, stored[index].quantityGrams)
            stored[index].quantityGrams -= taken
            remaining -= taken
        }
        stored.removeAll { $0.quantityGrams <= 0 }
        return touched
    }

    func record(_ events: [PantryEvent]) throws {
        try failIfNeeded()
        if let eventFailure { throw eventFailure }
        loggedEvents += events
    }

    func removeEvents(_ ids: [PantryEventID]) throws {
        try failIfNeeded()
        loggedEvents.removeAll { ids.contains($0.id) }
    }

    func events(from start: Date, to end: Date) throws -> [PantryEvent] {
        try failIfNeeded()
        return loggedEvents.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
    }

    private func failIfNeeded() throws {
        if let failure { throw failure }
    }
}

/// An in-memory food catalogue whose search matches any query word that starts, or is started by, a word of a food name; set `failure` to make every call throw.
actor FakeFoodRepository: FoodRepository {
    private var stored: [Food]
    var failure: LarderError?

    init(foods: [Food] = []) {
        self.stored = foods
    }

    func setFailure(_ failure: LarderError?) {
        self.failure = failure
    }

    func search(text: String, limit: Int) throws -> [Food] {
        try failIfNeeded()
        let queryWords = Self.words(in: text)
        let hits = stored.filter { food in
            Self.words(in: food.name).contains { name in queryWords.contains { $0.hasPrefix(name) || name.hasPrefix($0) } }
        }
        return Array(hits.prefix(limit))
    }

    func food(by id: FoodID) throws -> Food? {
        try failIfNeeded()
        return stored.first { $0.id == id }
    }

    func foods(byIDs ids: [FoodID]) throws -> [Food] {
        try failIfNeeded()
        return stored.filter { ids.contains($0.id) }
    }

    func food(byGTIN gtin: String) throws -> Food? {
        try failIfNeeded()
        let spellings = GTIN.spellings(of: gtin)
        return stored.first { food in food.gtin.map(spellings.contains) ?? false }
    }

    func upsert(_ foods: [Food]) throws {
        try failIfNeeded()
        for food in foods {
            if let index = stored.firstIndex(where: { $0.id == food.id }) {
                stored[index] = food
            } else {
                stored.append(food)
            }
        }
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    private func failIfNeeded() throws {
        if let failure { throw failure }
    }
}

/// An assistant that answers `parsePantry` with a scripted result and records the texts it was given.
actor FakeAssistant: AssistantBackend {
    private let script: Result<[ParsedPantryLine], LarderError>
    private(set) var receivedTexts: [String] = []

    init(returning lines: [ParsedPantryLine] = []) {
        self.script = .success(lines)
    }

    init(throwing error: LarderError) {
        self.script = .failure(error)
    }

    func parsePantry(text: String) throws -> [ParsedPantryLine] {
        receivedTexts.append(text)
        return try script.get()
    }

    func explain(plan: PlanExplainRequest) throws -> PlanExplanation {
        throw LarderError.assistantUnavailable
    }

    func parseRecipe(text: String, imageData: Data?) throws -> ParsedRecipe {
        throw LarderError.assistantUnavailable
    }

    func adjust(request: AdjustRequest) throws -> ConstraintEdit {
        throw LarderError.assistantUnavailable
    }
}

/// A clock that always reads the same instant.
nonisolated struct FixedDateProvider: DateProvider {
    let now: Date

    init(_ now: Date) {
        self.now = now
    }
}
#endif
