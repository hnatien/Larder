import Foundation
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
}

/// The grocery tab's state: the list for the plan's planned meals, ticks, and hand-written items.
@Observable @MainActor
public final class GroceryModel {
    public internal(set) var list: GroceryList?
    public private(set) var checked: Set<GroceryItemKey> = []
    public private(set) var manualItems: [ManualItem] = []
    public private(set) var isLoading = false
    public private(set) var error: GroceryError?

    private let plans: any PlanRepository
    private let recipes: any RecipeRepository
    private let foods: any FoodRepository
    private let pantry: any PantryRepository
    private let dates: any DateProvider
    private let locale: Locale
    private var foodsByID: [FoodID: Food] = [:]
    private var createdPantryItems: [GroceryItemKey: PantryItemID] = [:]

    /// Creates a model over the repositories; `locale` formats quantities.
    public init(
        plans: any PlanRepository,
        recipes: any RecipeRepository,
        foods: any FoodRepository,
        pantry: any PantryRepository,
        dates: any DateProvider,
        locale: Locale = .current
    ) {
        self.plans = plans
        self.recipes = recipes
        self.foods = foods
        self.pantry = pantry
        self.dates = dates
        self.locale = locale
    }

    /// Whether there is nothing to buy.
    public var isEmpty: Bool { entries.isEmpty }

    /// Unchecked entries by aisle in store-walk order; planned items first, then hand-written ones.
    public var toBuy: [GroceryEntrySection] { sections(checked: false) }

    /// Checked entries by aisle in store-walk order.
    public var basket: [GroceryEntrySection] { sections(checked: true) }

    /// Builds the list for the current plan's planned meals, net of the pantry.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
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
            let created = Set(createdPantryItems.values)
            let shelves = try await pantry.items().filter { !created.contains($0.id) }
            foodsByID = Dictionary(loadedFoods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            list = GroceryListBuilder().build(
                meals: meals, recipes: recipesByID, ingredients: ingredientsByRecipe,
                foods: foodsByID, pantry: shelves
            )
            let live = Set(entries.map(\.key))
            checked.formIntersection(live)
            createdPantryItems = createdPantryItems.filter { live.contains($0.key) }
            error = nil
        } catch {
            self.error = .loadFailed
        }
    }

    /// Ticks or unticks a planned item. Ticking a weighed item puts it on the shelves; unticking takes it off again.
    public func toggle(_ item: GroceryItem) async {
        let key = GroceryItemKey(item)
        if checked.contains(key) {
            if let pantryID = createdPantryItems[key] {
                do {
                    try await pantry.remove(pantryID)
                } catch {
                    self.error = .pantryUpdateFailed
                    return
                }
                createdPantryItems[key] = nil
            }
            checked.remove(key)
            error = nil
            return
        }
        if let pantryItem = pantryItem(for: item) {
            do {
                try await pantry.upsert(pantryItem)
            } catch {
                self.error = .pantryUpdateFailed
                return
            }
            createdPantryItems[key] = pantryItem.id
        }
        checked.insert(key)
        error = nil
    }

    /// Ticks or unticks a hand-written item.
    public func toggle(_ item: ManualItem) {
        let key = GroceryItemKey(item)
        if checked.contains(key) { checked.remove(key) } else { checked.insert(key) }
    }

    /// Ticks or unticks a line of either kind.
    public func toggle(_ entry: GroceryEntry) async {
        switch entry {
        case .planned(let item): await toggle(item)
        case .manual(let item): toggle(item)
        }
    }

    /// Adds a hand-written item; blank names are ignored.
    public func addManual(name: String, quantity: String = "", aisle: Aisle = .other) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        manualItems.append(ManualItem(name: name, quantity: quantity.trimmingCharacters(in: .whitespacesAndNewlines), aisle: aisle))
    }

    /// Removes a hand-written item.
    public func removeManual(_ item: ManualItem) {
        manualItems.removeAll { $0.id == item.id }
        checked.remove(GroceryItemKey(item))
    }

    /// Clears the basket. Bought items stay on the shelves.
    public func clearChecked() {
        let basketKeys = checked
        manualItems.removeAll { basketKeys.contains(GroceryItemKey($0)) }
        if let list {
            self.list = GroceryList(sections: list.sections.compactMap { section in
                let remaining = section.items.filter { !basketKeys.contains(GroceryItemKey($0)) }
                return remaining.isEmpty ? nil : GrocerySection(aisle: section.aisle, items: remaining)
            })
        }
        checked = []
        createdPantryItems = [:]
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

    private var entries: [GroceryEntry] {
        (list?.items.map(GroceryEntry.planned) ?? []) + manualItems.map(GroceryEntry.manual)
    }

    private func sections(checked wantChecked: Bool) -> [GroceryEntrySection] {
        let wanted = entries.filter { checked.contains($0.key) == wantChecked }
        return Aisle.allCases.compactMap { aisle in
            let inAisle = wanted.filter { $0.aisle == aisle }
            return inAisle.isEmpty ? nil : GroceryEntrySection(aisle: aisle, entries: inAisle)
        }
    }

    private func pantryItem(for item: GroceryItem) -> PantryItem? {
        guard let grams = item.neededGrams, let foodID = item.foodID, let food = foodsByID[foodID] else { return nil }
        let location: StorageLocation = switch food.foodGroup {
        case .dairy, .protein, .produce: .fridge
        case .grains, .fats, .legumes, .other: .pantry
        }
        return PantryItem(
            foodID: foodID, rawName: GroceryCopy.shoppingName(item.name), quantityGrams: grams, location: location,
            source: .manual, addedOn: dates.now
        )
    }
}
