import Foundation
import LarderCore
import Observation

/// What went wrong in the library, in terms the screen can word.
public nonisolated enum RecipesError: Error, Hashable, Sendable {
    case loadFailed
    case saveFailed
    case deleteFailed
    /// Only recipes the user imported can be deleted.
    case notDeletable
    /// A favourite or a hidden recipe could not be saved.
    case markFailed
}

/// How much of a recipe's food is on the shelves: lines matched to a food, and how many of those you have.
public nonisolated struct PantryCoverage: Hashable, Sendable {
    public var have: Int
    public var total: Int

    /// Creates a coverage count.
    public init(have: Int, total: Int) {
        self.have = have
        self.total = total
    }

    /// The share of matched lines on the shelves, from 0 to 1; 0 when nothing is matched.
    public var fraction: Double { total == 0 ? 0 : Double(have) / Double(total) }

    /// The coverage of `ingredients` by `pantry`: optional lines and garnish are left out, and each food counts once.
    public static func of(_ ingredients: [Ingredient], pantry: Set<FoodID>) -> PantryCoverage {
        let foods = Set(ingredients.filter { !$0.isOptional && !$0.isGarnish }.compactMap(\.foodID))
        return PantryCoverage(have: foods.intersection(pantry).count, total: foods.count)
    }
}

/// The recipe library: list, search, filters, detail, import and delete.
@Observable
@MainActor
public final class RecipesModel {
    /// The most search hits shown.
    static let searchLimit = 200

    public private(set) var recipes: [Recipe] = []
    /// Text for full-text search; empty shows every recipe.
    public var query = ""
    public var filters = RecipeFilters()
    public var sort = RecipeSort.name
    /// The recipes marked as favourites.
    public private(set) var favourites: Set<RecipeID> = []
    /// The recipes hidden from the library, for showing them again.
    public private(set) var hiddenRecipes: [Recipe] = []
    /// How much of each recipe is on the shelves.
    public private(set) var coverage: [RecipeID: PantryCoverage] = [:]
    public private(set) var isLoading = false
    /// Whether the library has been read at least once.
    public private(set) var hasLoaded = false
    public private(set) var error: RecipesError?

    private var candidates: [Recipe] = []
    private let repository: any RecipeRepository
    private let photos: any RecipePhotoStore
    private let foods: any FoodRepository
    private let profile: any ProfileRepository
    private let pantry: any PantryRepository
    private let marks: any RecipeMarkRepository
    private let assistant: any AssistantBackend
    private let isPlus: @Sendable () async -> Bool

    /// Creates a model over the given repositories; `pantry` says what you have for each recipe, `marks` keeps
    /// favourites and hidden recipes, and `isPlus` says whether the assistant may read pages.
    public init(
        recipes: any RecipeRepository,
        photos: any RecipePhotoStore,
        foods: any FoodRepository,
        profile: any ProfileRepository,
        pantry: any PantryRepository,
        marks: any RecipeMarkRepository,
        assistant: any AssistantBackend,
        isPlus: @escaping @Sendable () async -> Bool
    ) {
        self.repository = recipes
        self.photos = photos
        self.foods = foods
        self.profile = profile
        self.pantry = pantry
        self.marks = marks
        self.assistant = assistant
        self.isPlus = isPlus
    }

    /// Search hits or the whole library, with the filters applied, in the chosen order; search hits keep their
    /// best-match order unless another sort is chosen.
    public var results: [Recipe] {
        let filtered = candidates.filter { filters.matches($0) && (!filters.favouritesOnly || favourites.contains($0.id)) }
        switch sort {
        case .name:
            return filtered
        case .quickest:
            return filtered.sorted { ($0.prepMinutes + $0.cookMinutes, $0.title) < ($1.prepMinutes + $1.cookMinutes, $1.title) }
        case .mostInPantry:
            return filtered.sorted { lhs, rhs in
                let left = coverage[lhs.id]?.fraction ?? 0
                let right = coverage[rhs.id]?.fraction ?? 0
                return left == right ? lhs.title < rhs.title : left > right
            }
        }
    }

    /// Cuisines present in the library, sorted, for the cuisine filter.
    public var cuisines: [String] {
        Set(recipes.compactMap(\.tags.cuisine)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Loads every recipe and refreshes the results.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            recipes = try await repository.all()
            favourites = try await marks.favourites()
            hiddenRecipes = try await marks.hiddenRecipes()
            hasLoaded = true
            error = nil
        } catch {
            self.error = .loadFailed
            return
        }
        await refreshCandidates()
        await refreshCoverage()
    }

    /// Recounts what each recipe has on the shelves, after the pantry changed; a failed read keeps the last counts.
    public func refreshCoverage() async {
        do {
            let onShelves = try await pantryFoodIDs()
            var counts: [RecipeID: PantryCoverage] = [:]
            for recipe in recipes {
                counts[recipe.id] = PantryCoverage.of(try await repository.ingredients(for: recipe.id), pantry: onShelves)
            }
            coverage = counts
        } catch {
            return
        }
    }

    /// Marks a recipe as a favourite, or unmarks it.
    public func toggleFavourite(_ recipe: Recipe) async {
        let isFavourite = !favourites.contains(recipe.id)
        do {
            try await marks.setFavourite(recipe.id, isFavourite)
        } catch {
            self.error = .markFailed
            return
        }
        if isFavourite { favourites.insert(recipe.id) } else { favourites.remove(recipe.id) }
    }

    /// Hides a recipe from the library and from planning; it stays readable for plans that already use it.
    public func hide(_ recipe: Recipe) async {
        do {
            try await marks.setHidden(recipe.id, true)
        } catch {
            self.error = .markFailed
            return
        }
        await load()
    }

    /// Shows a hidden recipe again.
    public func unhide(_ recipe: Recipe) async {
        do {
            try await marks.setHidden(recipe.id, false)
        } catch {
            self.error = .markFailed
            return
        }
        await load()
    }

    private func pantryFoodIDs() async throws -> Set<FoodID> {
        Set(try await pantry.items().filter { $0.quantityGrams > 0 }.compactMap(\.foodID))
    }

    /// Refreshes the results for the current `query`, loading the library first if needed.
    public func search() async {
        guard hasLoaded else { return await load() }
        await refreshCandidates()
    }

    /// Everything the detail screen shows for `recipe`; throws when the data cannot be read, never a partial detail.
    public func detail(for recipe: Recipe) async throws -> RecipeDetail {
        let ingredients = try await repository.ingredients(for: recipe.id)
        let foodList = try await foods.foods(byIDs: ingredients.compactMap(\.foodID))
        let foodsByID = Dictionary(foodList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let constraints = try await profile.constraints()
        let showsNumbers = try await profile.profile()?.showsNumbers ?? false
        return RecipeDetail(
            recipe: recipe,
            ingredients: ingredients,
            nutrition: NutritionCalculator().nutrition(for: recipe, ingredients: ingredients, foods: foodsByID),
            verdict: ConstraintFilter().verdict(recipe: recipe, ingredients: ingredients, foods: foodsByID, constraints: constraints),
            showsNumbers: showsNumbers,
            pantryFoods: try await pantryFoodIDs(),
            hasConstraints: !constraints.isEmpty
        )
    }

    /// Deletes a recipe the user imported; any other recipe sets `error` to `.notDeletable` and stays. Returns whether it was deleted.
    @discardableResult
    public func delete(_ recipe: Recipe) async -> Bool {
        guard recipe.origin == .userImport else {
            error = .notDeletable
            return false
        }
        do {
            try await repository.delete(recipe.id)
        } catch {
            self.error = .deleteFailed
            return false
        }
        if let photo = recipe.photoFileName {
            // The recipe is gone either way; a file that cannot be removed is never shown and goes with Delete all data.
            try? await photos.delete(photo)
        }
        error = nil
        await load()
        return true
    }

    /// A model for the import sheet that saves into this library.
    public func makeImportModel() -> ImportModel {
        let importer = RecipeImporter(foods: foods, profile: profile, assistant: assistant, isPlus: isPlus)
        let profiles = profile
        return ImportModel(importer: importer, allowAI: {
            do {
                guard var stored = try await profiles.profile() else { return false }
                stored.consents.aiProcessing = true
                try await profiles.save(stored)
                return true
            } catch {
                return false
            }
        }) { [self] result in
            try await save(result)
        }
    }

    /// Saves an imported recipe, with its photo when it has one, and reloads the library.
    func save(_ result: ImportResult) async throws {
        var recipe = result.recipe
        do {
            if let photo = result.photo {
                recipe.photoFileName = try await photos.save(photo, for: recipe.id)
            }
            try await repository.save(recipe, ingredients: result.ingredients)
        } catch {
            if let photo = recipe.photoFileName {
                // Nothing refers to the file once the save failed; leaving it would only take up space.
                try? await photos.delete(photo)
            }
            self.error = .saveFailed
            throw RecipesError.saveFailed
        }
        await load()
    }

    /// Clears `error` once the screen has shown it.
    public func dismissError() {
        error = nil
    }

    private func refreshCandidates() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            candidates = recipes
            return
        }
        do {
            let hits = try await repository.search(text: text, limit: Self.searchLimit)
            guard !Task.isCancelled else { return }
            candidates = hits
        } catch {
            guard !Task.isCancelled else { return }
            candidates = []
            self.error = .loadFailed
        }
    }
}
