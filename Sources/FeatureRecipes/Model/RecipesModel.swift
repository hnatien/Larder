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
    public private(set) var isLoading = false
    /// Whether the library has been read at least once.
    public private(set) var hasLoaded = false
    public private(set) var error: RecipesError?

    private var candidates: [Recipe] = []
    private let repository: any RecipeRepository
    private let photos: any RecipePhotoStore
    private let foods: any FoodRepository
    private let profile: any ProfileRepository
    private let assistant: any AssistantBackend
    private let isPlus: @Sendable () async -> Bool

    /// Creates a model over the given repositories; `isPlus` says whether the assistant may read pages.
    public init(
        recipes: any RecipeRepository,
        photos: any RecipePhotoStore,
        foods: any FoodRepository,
        profile: any ProfileRepository,
        assistant: any AssistantBackend,
        isPlus: @escaping @Sendable () async -> Bool
    ) {
        self.repository = recipes
        self.photos = photos
        self.foods = foods
        self.profile = profile
        self.assistant = assistant
        self.isPlus = isPlus
    }

    /// Search hits or the whole library, with the filters applied.
    public var results: [Recipe] { candidates.filter(filters.matches) }

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
            hasLoaded = true
            error = nil
        } catch {
            self.error = .loadFailed
            return
        }
        await refreshCandidates()
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
            showsNumbers: showsNumbers
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
        return ImportModel(importer: importer) { [self] result in
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
