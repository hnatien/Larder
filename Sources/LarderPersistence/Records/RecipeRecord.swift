import Foundation
import GRDB
import LarderCore

struct RecipeRecord: LarderRecord {
    static let databaseTableName = "recipe"

    var id: UUID
    var title: String
    var origin: RecipeOrigin
    var sourceURL: URL?
    var license: String?
    var servings: Int
    var prepMinutes: Int
    var cookMinutes: Int
    var steps: [RecipeStep]
    var cuisine: String?
    var mealTypes: [MealType]
    var equipment: [Equipment]
    var dietFlags: [DietPattern]

    init(_ recipe: Recipe) {
        id = recipe.id.rawValue
        title = recipe.title
        origin = recipe.origin
        sourceURL = recipe.sourceURL
        license = recipe.license
        servings = recipe.servings
        prepMinutes = recipe.prepMinutes
        cookMinutes = recipe.cookMinutes
        steps = recipe.steps
        cuisine = recipe.tags.cuisine
        mealTypes = recipe.tags.mealTypes.sortedByRawValue
        equipment = recipe.tags.equipment.sortedByRawValue
        dietFlags = recipe.tags.dietFlags.sortedByRawValue
    }

    var recipe: Recipe {
        Recipe(
            id: RecipeID(rawValue: id),
            title: title,
            origin: origin,
            sourceURL: sourceURL,
            license: license,
            servings: servings,
            prepMinutes: prepMinutes,
            cookMinutes: cookMinutes,
            steps: steps,
            tags: RecipeTags(
                cuisine: cuisine,
                mealTypes: Set(mealTypes),
                equipment: Set(equipment),
                dietFlags: Set(dietFlags)
            )
        )
    }
}

struct IngredientRecord: LarderRecord {
    static let databaseTableName = "ingredient"

    var id: UUID
    var recipeID: UUID
    var position: Int
    var rawText: String
    var quantity: Double
    var unit: UnitOfMeasure
    var foodID: UUID?
    var gramsResolved: Double?
    var matchConfidence: Double
    var isOptional: Bool
    var isGarnish: Bool

    init(_ ingredient: Ingredient, position: Int) {
        id = ingredient.id.rawValue
        recipeID = ingredient.recipeID.rawValue
        self.position = position
        rawText = ingredient.rawText
        quantity = ingredient.quantity
        unit = ingredient.unit
        foodID = ingredient.foodID?.rawValue
        gramsResolved = ingredient.gramsResolved
        matchConfidence = ingredient.matchConfidence
        isOptional = ingredient.isOptional
        isGarnish = ingredient.isGarnish
    }

    var ingredient: Ingredient {
        Ingredient(
            id: IngredientID(rawValue: id),
            recipeID: RecipeID(rawValue: recipeID),
            rawText: rawText,
            quantity: quantity,
            unit: unit,
            foodID: foodID.map(FoodID.init(rawValue:)),
            gramsResolved: gramsResolved,
            matchConfidence: matchConfidence,
            isOptional: isOptional,
            isGarnish: isGarnish
        )
    }
}
