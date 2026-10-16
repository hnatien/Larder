import Foundation

/// One ingredient line of a recipe, as written and as resolved to a food and grams.
public struct Ingredient: Identifiable, Hashable, Codable, Sendable {
    public var id: IngredientID
    public var recipeID: RecipeID
    public var rawText: String
    public var quantity: Double
    public var unit: UnitOfMeasure
    public var foodID: FoodID?
    public var gramsResolved: Double?
    /// Confidence of the food match, from 0 to 1.
    public var matchConfidence: Double
    public var isOptional: Bool
    public var isGarnish: Bool

    /// Creates an ingredient line.
    public init(
        id: IngredientID = IngredientID(),
        recipeID: RecipeID,
        rawText: String,
        quantity: Double,
        unit: UnitOfMeasure,
        foodID: FoodID? = nil,
        gramsResolved: Double? = nil,
        matchConfidence: Double = 0,
        isOptional: Bool = false,
        isGarnish: Bool = false
    ) {
        self.id = id
        self.recipeID = recipeID
        self.rawText = rawText
        self.quantity = quantity
        self.unit = unit
        self.foodID = foodID
        self.gramsResolved = gramsResolved
        self.matchConfidence = matchConfidence
        self.isOptional = isOptional
        self.isGarnish = isGarnish
    }
}
