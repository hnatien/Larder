import Foundation
import LarderAssistant
import LarderCore
import Observation

/// One line on screen: a planned item or a hand-written one.
public enum GroceryEntry: Identifiable, Hashable, Sendable {
    case planned(GroceryItem)
    case manual(ManualItem)

    public var key: GroceryItemKey {
        switch self {
        case .planned(let item): GroceryItemKey(item)
        case .manual(let item): GroceryItemKey(item)
        }
    }

    public var id: GroceryItemKey { key }

    public var name: String {
        switch self {
        case .planned(let item): GroceryCopy.shoppingName(item.name)
        case .manual(let item): item.name
        }
    }

    public var aisle: Aisle {
        switch self {
        case .planned(let item): item.aisle
        case .manual(let item): item.aisle
        }
    }

    /// Whether the pantry already holds some of this food.
    public var partiallyInPantry: Bool {
        if case .planned(let item) = self { item.partiallyInPantry } else { false }
    }

    /// The quantity as shown, or empty for a manual item without one.
    public func quantityText(locale: Locale) -> String {
        switch self {
        case .planned(let item): item.displayQuantity.formatted(locale: locale)
        case .manual(let item): item.quantity
        }
    }
}

/// Entries of one aisle.
public struct GroceryEntrySection: Identifiable, Hashable, Sendable {
    public var aisle: Aisle
    public var entries: [GroceryEntry]

    public var id: Aisle { aisle }
}

/// Why the grocery list could not be loaded or updated.
public enum GroceryError: Error, Equatable, Sendable {
    case loadFailed
    case pantryUpdateFailed
    case basketUpdateFailed
}

/// The grocery tab's state: the list for the plan's planned meals, ticks, and hand-written items.
///
/// Ticks and hand-written items are stored, so a relaunch keeps them and a plan change never drops them: a ticked
/// planned item stays in the basket as it was when ticked, even once the plan stops needing it.
@Observable @MainActor
public final class GroceryModel {
    public internal(set) var list: GroceryList?
    public private(set) var manualItems: [ManualItem] = []
    public private(set) var isLoading = false
    public private(set) var error: GroceryError?
    /// Ticked lines in the order they were ticked.
    private var basketLines: [BasketLine] = []

    private let plans: any PlanRepository
    private let recipes: any RecipeRepository
    private let foods: any FoodRepository
    private let pantry: any PantryRepository
    private let basketStore: any GroceryBasketRepository
    private let dates: any DateProvider
    private let calendar: Calendar
    private let locale: Locale
    private var foodsByID: [FoodID: Food] = [:]

    /// Creates a model over the repositories; `basket` keeps ticks and hand-written items, `calendar` counts best-by
    /// days and `locale` formats quantities.
    public init(
        plans: any PlanRepository,
        recipes: any RecipeRepository,
        foods: any FoodRepository,
        pantry: any PantryRepository,
        basket: any GroceryBasketRepository,
        dates: any DateProvider,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        self.plans = plans
        self.recipes = recipes
        self.foods = foods
        self.pantry = pantry
        self.basketStore = basket
        self.dates = dates
        self.calendar = calendar
        self.locale = locale
    }

    /// The keys of the ticked lines.
    public var checked: Set<GroceryItemKey> { Set(basketLines.map(\.key)) }

    /// Whether there is nothing to buy and nothing in the basket.
    public var isEmpty: Bool { unchecked.isEmpty && basketEntries.isEmpty }

    /// Unchecked entries by aisle in store-walk order; planned items first, then hand-written ones.
    public var toBuy: [GroceryEntrySection] { sections(unchecked) }

    /// Checked entries by aisle in store-walk order, in the order they were ticked.
    public var basket: [GroceryEntrySection] { sections(basketEntries) }

    /// Reads the basket and hand-written items, then builds the list for the current plan's planned meals, net of
    /// the pantry. Food a tick put on the shelves is not subtracted, so its line stays on the list.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let storedManualItems = try await basketStore.manualItems()
            let storedLines = try await basketStore.basketLines()
            manualItems = storedManualItems
            basketLines = storedLines
            guard let plan = try await plans.currentPlan() else {
                list = GroceryList(sections: [])
                foodsByID = [:]
                error = nil
                return
            }
            let meals = try await plans.meals(for: plan.id)
            var recipesByID: [RecipeID: Recipe] = [:]
            var ingredientsByRecipe: [RecipeID: [Ingredient]] = [:]
            for recipeID in Set(meals.map(\.recipeID)) {
                guard let recipe = try await recipes.recipe(by: recipeID) else { continue }
                recipesByID[recipeID] = recipe
                ingredientsByRecipe[recipeID] = try await recipes.ingredients(for: recipeID)
            }
            let foodIDs = Set(ingredientsByRecipe.values.flatMap { $0 }.compactMap(\.foodID))
            let loadedFoods = try await foods.foods(byIDs: Array(foodIDs))
            let landed = Set(storedLines.compactMap(\.pantryItemID))
            let shelves = try await pantry.items().filter { !landed.contains($0.id) }
            foodsByID = Dictionary(loadedFoods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            list = GroceryListBuilder().build(
                meals: meals, recipes: recipesByID, ingredients: ingredientsByRecipe,
                foods: foodsByID, pantry: shelves
            )
            error = nil
        } catch {
            self.error = .loadFailed
        }
    }

    /// Ticks or unticks a planned item. Ticking puts it on the shelves with a default best-by date; unticking takes
    /// it off again.
    public func toggle(_ item: GroceryItem) async {
        let key = GroceryItemKey(item)
        if let line = basketLines.first(where: { $0.key == key }) {
            await untick(line)
            return
        }
        await tick(BasketLine(key: key, item: item, pantryItemID: nil, checkedOn: dates.now), landing: landedItem(for: item))
    }

    /// Ticks or unticks a hand-written item. Ticking one that names a known food puts it on the shelves; anything
    /// else, such as candles, only ticks.
    public func toggle(_ item: ManualItem) async {
        let key = GroceryItemKey(item)
        if let line = basketLines.first(where: { $0.key == key }) {
            await untick(line)
            return
        }
        let landing: PantryItem?
        do {
            landing = try await landedItem(for: item)
        } catch {
            self.error = .pantryUpdateFailed
            return
        }
        await tick(BasketLine(key: key, item: nil, pantryItemID: nil, checkedOn: dates.now), landing: landing)
    }

    /// Ticks or unticks a line of either kind.
    public func toggle(_ entry: GroceryEntry) async {
        switch entry {
        case .planned(let item): await toggle(item)
        case .manual(let item): await toggle(item)
        }
    }

    /// Adds a hand-written item; blank names are ignored.
    public func addManual(name: String, quantity: String = "", aisle: Aisle = .other) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let item = ManualItem(name: name, quantity: quantity.trimmingCharacters(in: .whitespacesAndNewlines), aisle: aisle)
        do {
            try await basketStore.saveManualItem(item)
        } catch {
            self.error = .basketUpdateFailed
            return
        }
        manualItems.append(item)
        error = nil
    }

    /// Removes a hand-written item and its tick; food the tick put on the shelves stays there.
    public func removeManual(_ item: ManualItem) async {
        do {
            try await basketStore.removeManualItem(item.id)
        } catch {
            self.error = .basketUpdateFailed
            return
        }
        manualItems.removeAll { $0.id == item.id }
        basketLines.removeAll { $0.key == GroceryItemKey(item) }
        error = nil
    }

    /// Clears the basket. Bought items stay on the shelves.
    public func clearChecked() async {
        do {
            try await basketStore.clearBasket()
        } catch {
            self.error = .basketUpdateFailed
            return
        }
        let basketKeys = checked
        manualItems.removeAll { basketKeys.contains(GroceryItemKey($0)) }
        if let list {
            self.list = GroceryList(sections: list.sections.compactMap { section in
                let remaining = section.items.filter { !basketKeys.contains(GroceryItemKey($0)) }
                return remaining.isEmpty ? nil : GrocerySection(aisle: section.aisle, items: remaining)
            })
        }
        basketLines = []
        error = nil
    }

    /// Plain text for the share sheet: aisle headings with "- quantity name" lines, unchecked items only.
    public func shareText() -> String {
        toBuy.map { section in
            let lines = section.entries.map { entry in
                let quantity = entry.quantityText(locale: locale)
                return quantity.isEmpty ? "- \(entry.name)" : "- \(quantity) \(entry.name)"
            }
            return ([GroceryCopy.name(of: section.aisle)] + lines).joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    /// Formats a planned item's quantity as shown on screen.
    func quantityText(_ entry: GroceryEntry) -> String { entry.quantityText(locale: locale) }

    /// Planned items from the list and hand-written items that are not ticked.
    private var unchecked: [GroceryEntry] {
        let ticked = checked
        let entries = (list?.items.map(GroceryEntry.planned) ?? []) + manualItems.map(GroceryEntry.manual)
        return entries.filter { !ticked.contains($0.key) }
    }

    /// Ticked lines as entries: a planned item as it was ticked, a hand-written item as it is now.
    private var basketEntries: [GroceryEntry] {
        let manualByKey = Dictionary(manualItems.map { (GroceryItemKey($0), $0) }, uniquingKeysWith: { first, _ in first })
        return basketLines.compactMap { line in
            if let item = line.item { return .planned(item) }
            return manualByKey[line.key].map(GroceryEntry.manual)
        }
    }

    private func sections(_ entries: [GroceryEntry]) -> [GroceryEntrySection] {
        Aisle.allCases.compactMap { aisle in
            let inAisle = entries.filter { $0.aisle == aisle }
            return inAisle.isEmpty ? nil : GroceryEntrySection(aisle: aisle, entries: inAisle)
        }
    }

    /// Stores the tick, then puts `landing` on the shelves; if the shelves cannot take it, the tick is taken back.
    private func tick(_ line: BasketLine, landing: PantryItem?) async {
        var line = line
        line.pantryItemID = landing?.id
        do {
            try await basketStore.saveBasketLine(line)
        } catch {
            self.error = .basketUpdateFailed
            return
        }
        if let landing {
            do {
                try await pantry.upsert(landing)
            } catch {
                self.error = .pantryUpdateFailed
                do {
                    try await basketStore.removeBasketLine(line.key)
                } catch {
                    // The stored tick stays, so show it; unticking later removes a shelf item that was never written, which is harmless.
                    basketLines.append(line)
                }
                return
            }
        }
        basketLines.append(line)
        error = nil
    }

    /// Takes the line's food off the shelves, then the tick off the basket.
    private func untick(_ line: BasketLine) async {
        if let pantryID = line.pantryItemID {
            do {
                try await pantry.remove(pantryID)
            } catch {
                self.error = .pantryUpdateFailed
                return
            }
        }
        do {
            try await basketStore.removeBasketLine(line.key)
        } catch {
            self.error = .basketUpdateFailed
            return
        }
        basketLines.removeAll { $0.key == line.key }
        error = nil
    }

    /// What a ticked planned item puts on the shelves, or `nil` when its amount is not positive.
    ///
    /// An amount the list could not weigh is converted with the food's density or first portion when it can be, and
    /// is otherwise stored as its number, as Add food stores an amount it cannot convert.
    private func landedItem(for item: GroceryItem) -> PantryItem? {
        let food = item.foodID.flatMap { foodsByID[$0] }
        let grams = item.neededGrams ?? Self.grams(item.displayQuantity, food: food)
        return shelfItem(name: GroceryCopy.shoppingName(item.name), food: food, foodID: item.foodID, grams: grams, source: .groceryList)
    }

    /// What a ticked hand-written item puts on the shelves: only one that names a known food, with the amount read
    /// from its quantity text, one piece when it has none.
    private func landedItem(for item: ManualItem) async throws -> PantryItem? {
        guard let food = try await foods.match(forItemNamed: item.name) else { return nil }
        let parsed = DeterministicPantryParser().parse("\(item.quantity) \(item.name)").first
        let quantity = Quantity(value: parsed?.quantity ?? 1, unit: parsed?.unit ?? .piece)
        return shelfItem(name: item.name, food: food, foodID: food.id, grams: Self.grams(quantity, food: food), source: .manual)
    }

    private func shelfItem(name: String, food: Food?, foodID: FoodID?, grams: Double, source: PantrySource) -> PantryItem? {
        guard grams.isFinite, grams > 0 else { return nil }
        let now = dates.now
        let location = StorageLocation.usual(forItemNamed: name, food: food)
        return PantryItem(
            foodID: foodID, rawName: name, quantityGrams: grams, location: location,
            bestBy: ShelfLife.bestBy(forItemNamed: name, food: food, in: location, addedOn: now, calendar: calendar),
            source: source, addedOn: now
        )
    }

    private static func grams(_ quantity: Quantity, food: Food?) -> Double {
        (try? UnitConverter.grams(
            from: quantity.value, unit: quantity.unit, density: food?.densityGPerMl, portion: food?.portions.first
        )) ?? quantity.value
    }
}
