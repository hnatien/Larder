import LarderCore

/// Library filters; an empty set or `nil` places no restriction on that field.
public nonisolated struct RecipeFilters: Hashable, Sendable {
    public var mealTypes: Set<MealType>
    public var dietFlags: Set<DietPattern>
    /// The most prep plus cook minutes a recipe may take.
    public var maxMinutes: Int?
    public var cuisine: String?

    /// Creates filters; the default places no restriction.
    public init(
        mealTypes: Set<MealType> = [],
        dietFlags: Set<DietPattern> = [],
        maxMinutes: Int? = nil,
        cuisine: String? = nil
    ) {
        self.mealTypes = mealTypes
        self.dietFlags = dietFlags
        self.maxMinutes = maxMinutes
        self.cuisine = cuisine
    }

    /// Whether no filter is active.
    public var isEmpty: Bool { self == RecipeFilters() }

    /// Whether `recipe` is in any chosen meal type, carries every chosen diet flag, is quick enough and has the chosen cuisine.
    public func matches(_ recipe: Recipe) -> Bool {
        if !mealTypes.isEmpty, mealTypes.isDisjoint(with: recipe.tags.mealTypes) { return false }
        if !dietFlags.isSubset(of: recipe.tags.dietFlags) { return false }
        if let maxMinutes, recipe.prepMinutes + recipe.cookMinutes > maxMinutes { return false }
        if let cuisine, recipe.tags.cuisine?.localizedCaseInsensitiveCompare(cuisine) != .orderedSame { return false }
        return true
    }
}
