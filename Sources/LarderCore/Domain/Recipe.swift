import Foundation

/// A recipe; its ingredient lines are stored separately as `Ingredient` values.
public struct Recipe: Identifiable, Hashable, Codable, Sendable {
    public var id: RecipeID
    public var title: String
    public var origin: RecipeOrigin
    public var sourceURL: URL?
    public var license: String?
    public var servings: Int
    public var prepMinutes: Int
    public var cookMinutes: Int
    public var steps: [RecipeStep]
    public var tags: RecipeTags
    /// The file name of the recipe's photo in the `RecipePhotoStore`; `nil` when the recipe has none.
    public var photoFileName: String?

    /// Creates a recipe.
    public init(
        id: RecipeID = RecipeID(),
        title: String,
        origin: RecipeOrigin,
        sourceURL: URL? = nil,
        license: String? = nil,
        servings: Int,
        prepMinutes: Int,
        cookMinutes: Int,
        steps: [RecipeStep] = [],
        tags: RecipeTags = RecipeTags(),
        photoFileName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.origin = origin
        self.sourceURL = sourceURL
        self.license = license
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.steps = steps
        self.tags = tags
        self.photoFileName = photoFileName
    }
}

/// Where a recipe came from.
public enum RecipeOrigin: String, Hashable, Codable, Sendable {
    case generated
    case usda
    case userImport
}

/// One instruction in a recipe, with an optional timer.
public struct RecipeStep: Hashable, Codable, Sendable {
    public var text: String
    public var timerSeconds: Int?

    /// Creates a step.
    public init(text: String, timerSeconds: Int? = nil) {
        self.text = text
        self.timerSeconds = timerSeconds
    }
}

/// Searchable and filterable attributes of a recipe.
public struct RecipeTags: Hashable, Codable, Sendable {
    public var cuisine: String?
    public var mealTypes: Set<MealType>
    public var equipment: Set<Equipment>
    public var dietFlags: Set<DietPattern>

    /// Creates recipe tags.
    public init(
        cuisine: String? = nil,
        mealTypes: Set<MealType> = [],
        equipment: Set<Equipment> = [],
        dietFlags: Set<DietPattern> = []
    ) {
        self.cuisine = cuisine
        self.mealTypes = mealTypes
        self.equipment = equipment
        self.dietFlags = dietFlags
    }
}

/// A meal of the day; also the slot a planned meal fills.
public enum MealType: String, CaseIterable, Hashable, Codable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack
}

/// Kitchen equipment a recipe needs or a user has.
public enum Equipment: String, CaseIterable, Hashable, Codable, Sendable {
    case oven
    case stovetop
    case microwave
    case airFryer
    case slowCooker
    case pressureCooker
    case blender
    case foodProcessor
    case grill
}
