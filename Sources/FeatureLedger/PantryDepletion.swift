import Foundation
import LarderCore

/// What cooking took off the shelves, kept so it can be put back.
public nonisolated struct ShelfDraw: Hashable, Sendable {
    /// The items cooking touched, as they were before.
    public var itemsBefore: [PantryItem]
    /// The `.cooked` events it logged.
    public var eventIDs: [PantryEventID]

    /// Creates a draw.
    public init(itemsBefore: [PantryItem] = [], eventIDs: [PantryEventID] = []) {
        self.itemsBefore = itemsBefore
        self.eventIDs = eventIDs
    }

    /// Whether cooking took nothing.
    public var isEmpty: Bool { itemsBefore.isEmpty }
}

/// Takes what a cooked meal used off the shelves, earliest best-by first, logs it, and puts it back on undo.
public nonisolated struct PantryDepletion: Sendable {
    private let recipes: any RecipeRepository
    private let foods: any FoodRepository
    private let pantry: any PantryRepository
    private let dates: any DateProvider

    /// Creates a depletion over the given ports.
    public init(recipes: any RecipeRepository, foods: any FoodRepository, pantry: any PantryRepository, dates: any DateProvider) {
        self.recipes = recipes
        self.foods = foods
        self.pantry = pantry
        self.dates = dates
    }

    /// Takes off what cooking `meal` used at its servings; a leftover takes nothing (see `CookingDraw`).
    public func deplete(cooking meal: PlannedMeal) async throws -> ShelfDraw {
        guard meal.leftoverOf == nil, let recipe = try await recipes.recipe(by: meal.recipeID) else { return ShelfDraw() }
        let (ingredients, foodsByID) = try await lines(of: recipe)
        let amounts = CookingDraw.amounts(cooking: meal, recipe: recipe, ingredients: ingredients, foods: foodsByID)
        return try await take(amounts, plannedMealID: meal.id)
    }

    /// Takes off what cooking `recipe` for `servings` used, for a recipe cooked outside the plan.
    public func deplete(cooking recipe: Recipe, servings: Int) async throws -> ShelfDraw {
        let (ingredients, foodsByID) = try await lines(of: recipe)
        let amounts = CookingDraw.amounts(recipe: recipe, servings: servings, ingredients: ingredients, foods: foodsByID)
        return try await take(amounts, plannedMealID: nil)
    }

    /// Puts back the items `draw` touched as they were, and drops its events.
    public func restore(_ draw: ShelfDraw) async throws {
        for item in draw.itemsBefore {
            try await pantry.upsert(item)
        }
        try await pantry.removeEvents(draw.eventIDs)
    }

    private func lines(of recipe: Recipe) async throws -> ([Ingredient], [FoodID: Food]) {
        let ingredients = try await recipes.ingredients(for: recipe.id)
        let loaded = try await foods.foods(byIDs: Array(Set(ingredients.compactMap(\.foodID))))
        return (ingredients, Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }))
    }

    /// Consumes each amount and logs what was actually on the shelves; a failure part way puts back what was taken.
    private func take(_ amounts: [FoodAmount], plannedMealID: PlannedMealID?) async throws -> ShelfDraw {
        let now = dates.now
        var draw = ShelfDraw()
        var events: [PantryEvent] = []
        do {
            for amount in amounts {
                let touched = try await pantry.consume(foodID: amount.foodID, grams: amount.grams)
                guard let first = touched.first else { continue }
                draw.itemsBefore += touched
                let taken = min(amount.grams, touched.map(\.quantityGrams).reduce(0, +))
                events.append(PantryEvent(
                    kind: .cooked, foodID: amount.foodID, name: first.rawName, grams: taken, date: now, plannedMealID: plannedMealID
                ))
            }
            try await pantry.record(events)
        } catch {
            // The first failure is the one to report; if putting things back fails too, the shelves stay as far as
            // cooking got.
            try? await restore(ShelfDraw(itemsBefore: draw.itemsBefore))
            throw error
        }
        draw.eventIDs = events.map(\.id)
        return draw
    }
}
