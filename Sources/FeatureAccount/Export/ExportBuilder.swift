import CoreTransferable
import Foundation
import LarderCore
import UniformTypeIdentifiers

/// Everything Larder stores about the user, as written to the export file.
public nonisolated struct LarderExport: Hashable, Codable, Sendable {
    /// The format version written by this build.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var exportedAt: Date
    public var profile: UserProfile?
    public var constraints: [DietaryConstraint]
    public var targets: [NutrientTarget]
    public var recipes: [RecipeEntry]
    public var pantry: [PantryItem]
    public var plans: [PlanEntry]

    /// A recipe with its ingredient lines.
    public struct RecipeEntry: Hashable, Codable, Sendable {
        public var recipe: Recipe
        public var ingredients: [Ingredient]
    }

    /// A plan with its meals.
    public struct PlanEntry: Hashable, Codable, Sendable {
        public var plan: MealPlan
        public var meals: [PlannedMeal]
    }
}

/// Reads every repository and writes one JSON document; dates are ISO 8601 with milliseconds.
public nonisolated struct ExportBuilder: Sendable {
    private let profiles: any ProfileRepository
    private let recipes: any RecipeRepository
    private let pantry: any PantryRepository
    private let plans: any PlanRepository

    /// Creates a builder over the repositories.
    public init(
        profiles: any ProfileRepository,
        recipes: any RecipeRepository,
        pantry: any PantryRepository,
        plans: any PlanRepository
    ) {
        self.profiles = profiles
        self.recipes = recipes
        self.pantry = pantry
        self.plans = plans
    }

    /// The export as JSON; throws whatever a repository throws.
    public func build(exportedAt: Date) async throws -> Data {
        try Self.encoder.encode(try await snapshot(exportedAt: exportedAt))
    }

    func snapshot(exportedAt: Date) async throws -> LarderExport {
        var recipeEntries: [LarderExport.RecipeEntry] = []
        for recipe in try await recipes.all() {
            recipeEntries.append(.init(recipe: recipe, ingredients: try await recipes.ingredients(for: recipe.id)))
        }
        var planEntries: [LarderExport.PlanEntry] = []
        for plan in try await plans.plans() {
            planEntries.append(.init(plan: plan, meals: try await plans.meals(for: plan.id)))
        }
        return LarderExport(
            formatVersion: LarderExport.currentFormatVersion,
            exportedAt: exportedAt,
            profile: try await profiles.profile(),
            constraints: try await profiles.constraints(),
            targets: try await profiles.targets(),
            recipes: recipeEntries,
            pantry: try await pantry.items(),
            plans: planEntries
        )
    }

    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return try dateStyle.parse(try container.decode(String.self))
        }
        return decoder
    }
}

/// The export as a shareable JSON file, built when the share sheet asks for it.
public nonisolated struct ExportDocument: Transferable, Sendable {
    let builder: ExportBuilder
    let dates: any DateProvider

    /// Creates a document that builds with `builder`, stamped with the time of export.
    public init(builder: ExportBuilder, dates: any DateProvider) {
        self.builder = builder
        self.dates = dates
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { document in
            try await document.builder.build(exportedAt: document.dates.now)
        }
        .suggestedFileName("larder-export.json")
    }
}
