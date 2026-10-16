import Foundation

/// One line of the grocery list.
public struct GroceryItem: Hashable, Sendable {
    public var name: String
    public var foodID: FoodID?
    /// Grams still to buy after the pantry; `nil` when the amount could not be weighed (see `displayQuantity`).
    public var neededGrams: Double?
    /// The amount in the unit the recipes use most, or grams when that unit cannot be converted back.
    public var displayQuantity: Quantity
    public var aisle: Aisle
    /// Whether the pantry already holds some of this food.
    public var partiallyInPantry: Bool
    public var forMeals: [PlannedMealID]

    /// Creates a grocery item.
    public init(
        name: String,
        foodID: FoodID?,
        neededGrams: Double?,
        displayQuantity: Quantity,
        aisle: Aisle,
        partiallyInPantry: Bool,
        forMeals: [PlannedMealID]
    ) {
        self.name = name
        self.foodID = foodID
        self.neededGrams = neededGrams
        self.displayQuantity = displayQuantity
        self.aisle = aisle
        self.partiallyInPantry = partiallyInPantry
        self.forMeals = forMeals
    }
}

/// Items of one aisle, sorted by name.
public struct GrocerySection: Hashable, Sendable {
    public var aisle: Aisle
    public var items: [GroceryItem]

    /// Creates a section.
    public init(aisle: Aisle, items: [GroceryItem]) {
        self.aisle = aisle
        self.items = items
    }
}

/// A grocery list grouped by aisle in store-walk order; empty aisles are left out.
public struct GroceryList: Hashable, Sendable {
    public var sections: [GrocerySection]

    /// Creates a list from sections.
    public init(sections: [GrocerySection]) {
        self.sections = sections
    }

    /// Every item, in store-walk order.
    public var items: [GroceryItem] { sections.flatMap(\.items) }
}

/// Builds a grocery list from planned meals, net of the pantry.
public struct GroceryListBuilder: Sendable {
    /// Creates a builder.
    public init() {}

    /// The list for `meals`.
    ///
    /// Only meals still planned are shopped for; cooked, skipped and leftover meals need nothing new.
    /// Ingredients scale by meal servings over recipe servings, garnish is skipped, and lines aggregate by
    /// food, or by normalised text when unmatched. Pantry grams of the same food are subtracted and fully
    /// covered items dropped. Lines that cannot be weighed aggregate separately per unit, without pantry
    /// subtraction, and are marked when the pantry holds that food.
    public func build(
        meals: [PlannedMeal],
        recipes: [RecipeID: Recipe],
        ingredients: [RecipeID: [Ingredient]],
        foods: [FoodID: Food],
        pantry: [PantryItem]
    ) -> GroceryList {
        var accumulators: [Key: Accumulator] = [:]
        var order: [Key] = []

        for meal in meals where meal.status == .planned && meal.leftoverOf == nil && meal.servings > 0 {
            guard let recipe = recipes[meal.recipeID] else { continue }
            let factor = Double(meal.servings) / Double(max(recipe.servings, 1))
            for ingredient in ingredients[meal.recipeID] ?? [] where !ingredient.isGarnish {
                let food = ingredient.foodID.flatMap { foods[$0] }
                let grams = IngredientGrams.resolve(ingredient, food: food)
                let identity: Identity = ingredient.foodID.map(Identity.food)
                    ?? .text(TermMatcher.words(ingredient.rawText).joined(separator: " "))
                let key = Key(identity: identity, unweighedUnit: grams == nil ? ingredient.unit : nil)
                if accumulators[key] == nil {
                    order.append(key)
                    accumulators[key] = Accumulator(name: food?.name ?? ingredient.rawText.trimmingCharacters(in: .whitespacesAndNewlines), food: food)
                }
                accumulators[key]?.add(ingredient, grams: grams.map { $0 * factor }, factor: factor, meal: meal.id)
            }
        }

        let pantryGrams = pantry.reduce(into: [FoodID: Double]()) { totals, item in
            guard let foodID = item.foodID, item.quantityGrams.isFinite, item.quantityGrams > 0 else { return }
            totals[foodID, default: 0] += item.quantityGrams
        }

        let items = order.compactMap { key -> GroceryItem? in
            guard let accumulator = accumulators[key] else { return nil }
            let foodID: FoodID? = if case .food(let id) = key.identity { id } else { nil }
            let inPantry = foodID.flatMap { pantryGrams[$0] } ?? 0
            return accumulator.item(foodID: foodID, unweighedUnit: key.unweighedUnit, pantryGrams: inPantry)
        }

        let sections = Aisle.allCases.compactMap { aisle -> GrocerySection? in
            let aisleItems = items.filter { $0.aisle == aisle }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return aisleItems.isEmpty ? nil : GrocerySection(aisle: aisle, items: aisleItems)
        }
        return GroceryList(sections: sections)
    }

    private enum Identity: Hashable {
        case food(FoodID)
        case text(String)
    }

    private struct Key: Hashable {
        var identity: Identity
        /// Set for lines that could not be weighed; they aggregate by unit instead of grams.
        var unweighedUnit: UnitOfMeasure?
    }

    private struct Accumulator {
        var name: String
        var food: Food?
        var grams = 0.0
        var unweighedQuantity = 0.0
        var unitCounts: [UnitOfMeasure: Int] = [:]
        var unitOrder: [UnitOfMeasure] = []
        var meals: [PlannedMealID] = []

        init(name: String, food: Food?) {
            self.name = name
            self.food = food
        }

        mutating func add(_ ingredient: Ingredient, grams: Double?, factor: Double, meal: PlannedMealID) {
            if let grams {
                self.grams += grams
            } else if ingredient.quantity.isFinite, ingredient.quantity >= 0 {
                unweighedQuantity += ingredient.quantity * factor
            }
            if unitCounts[ingredient.unit] == nil { unitOrder.append(ingredient.unit) }
            unitCounts[ingredient.unit, default: 0] += 1
            if !meals.contains(meal) { meals.append(meal) }
        }

        func item(foodID: FoodID?, unweighedUnit: UnitOfMeasure?, pantryGrams: Double) -> GroceryItem? {
            let aisle = Aisle.forItem(named: name, food: food)
            if let unweighedUnit {
                return GroceryItem(
                    name: name, foodID: foodID, neededGrams: nil,
                    displayQuantity: Quantity(value: unweighedQuantity, unit: unweighedUnit),
                    aisle: aisle, partiallyInPantry: pantryGrams > 0, forMeals: meals
                )
            }
            let needed = max(grams - pantryGrams, 0)
            guard needed > 0 else { return nil }
            return GroceryItem(
                name: name, foodID: foodID, neededGrams: needed,
                displayQuantity: displayQuantity(grams: needed),
                aisle: aisle, partiallyInPantry: pantryGrams > 0, forMeals: meals
            )
        }

        /// `grams` in the most frequent unit (ties go to the first seen), else in grams.
        private func displayQuantity(grams: Double) -> Quantity {
            guard let unit = unitOrder.max(by: { (unitCounts[$0] ?? 0) < (unitCounts[$1] ?? 0) }) else {
                return Quantity(value: grams, unit: .gram)
            }
            if let perUnit = unit.gramsPerUnit {
                return Quantity(value: grams / perUnit, unit: unit)
            }
            if let millilitres = unit.millilitresPerUnit, let density = food?.densityGPerMl, density.isFinite, density > 0 {
                return Quantity(value: grams / density / millilitres, unit: unit)
            }
            if let food, let portion = IngredientGrams.portion(for: unit, in: food), portion.grams.isFinite, portion.grams > 0 {
                return Quantity(value: grams / portion.grams, unit: unit)
            }
            return Quantity(value: grams, unit: .gram)
        }
    }
}
