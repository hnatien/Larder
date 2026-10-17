import LarderCore

/// How the library is ordered.
public nonisolated enum RecipeSort: String, CaseIterable, Hashable, Sendable {
    /// A to Z by title.
    case name
    /// Shortest prep plus cook time first.
    case quickest
    /// Most of the ingredients on the shelves first.
    case mostInPantry
}

/// Library filters; an empty set or `nil` places no restriction on that field.
public nonisolated struct RecipeFilters: Hashable, Sendable {
    public var mealTypes: Set<MealType>
    public var dietFlags: Set<DietPattern>
    /// The most prep plus cook minutes a recipe may take.
    public var maxMinutes: Int?
    public var cuisine: String?
    /// Whether only favourites show; the model applies it, since favourites are not part of a recipe.
    public var favouritesOnly: Bool

    /// Creates filters; the default places no restriction.
    public init(
        mealTypes: Set<MealType> = [],
        dietFlags: Set<DietPattern> = [],
        maxMinutes: Int? = nil,
        cuisine: String? = nil,
        favouritesOnly: Bool = false
    ) {
        self.mealTypes = mealTypes
        self.dietFlags = dietFlags
        self.maxMinutes = maxMinutes
        self.cuisine = cuisine
        self.favouritesOnly = favouritesOnly
    }

    /// How many filters are on, for the Filters button.
    public var activeCount: Int {
        mealTypes.count + dietFlags.count + (maxMinutes == nil ? 0 : 1) + (cuisine == nil ? 0 : 1) + (favouritesOnly ? 1 : 0)
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
