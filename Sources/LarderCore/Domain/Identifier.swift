import Foundation

/// A UUID-backed identifier typed by the entity it identifies, so a `FoodID` cannot be passed where a `RecipeID` is expected.
public struct Identifier<Tag>: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UUID

    /// Wraps an existing UUID.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// Creates a new random identifier.
    public init() {
        self.rawValue = UUID()
    }

    public init(from decoder: any Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Identifies a `Food`.
public typealias FoodID = Identifier<Food>
/// Identifies a `Recipe`.
public typealias RecipeID = Identifier<Recipe>
/// Identifies an `Ingredient` line.
public typealias IngredientID = Identifier<Ingredient>
/// Identifies a `PantryItem`.
public typealias PantryItemID = Identifier<PantryItem>
/// Identifies a `DietaryConstraint`.
public typealias DietaryConstraintID = Identifier<DietaryConstraint>
/// Identifies a `MealPlan`.
public typealias MealPlanID = Identifier<MealPlan>
/// Identifies a `PlannedMeal`.
public typealias PlannedMealID = Identifier<PlannedMeal>
