import Foundation
import LarderCore
import Testing
@testable import FeatureAccount

@Suite("ExportBuilder")
struct ExportBuilderTests {
    private let day = Date(timeIntervalSince1970: 1_792_108_800)

    private func populated() async -> (FakeProfileRepository, FakeLibrary, LarderExport) {
        let constraints = [
            DietaryConstraint.userSet(.allergen(.peanut), at: day),
            DietaryConstraint.userSet(.religious(.halal), at: day),
            DietaryConstraint.userSet(.dislike(.name("Coriander")), at: day),
        ]
        let targets = NutrientTargets.defaults(for: sampleProfile, constraints: constraints, referenceYear: 2026)
        let profiles = FakeProfileRepository(profile: sampleProfile, constraints: constraints, targets: targets)
        let library = FakeLibrary()
        let recipe = Recipe(
            title: "Lentil soup", origin: .usda, servings: 4, prepMinutes: 10, cookMinutes: 30,
            steps: [RecipeStep(text: "Simmer", timerSeconds: 1_200)],
            tags: RecipeTags(mealTypes: [.dinner], equipment: [.stovetop], dietFlags: [.vegan])
        )
        let ingredient = Ingredient(
            recipeID: recipe.id, rawText: "200 g red lentils", quantity: 200, unit: .gram,
            foodID: FoodID(), gramsResolved: 200, matchConfidence: 0.92
        )
        await library.save(recipe, ingredients: [ingredient])
        let item = PantryItem(rawName: "Rice", quantityGrams: 750, location: .pantry, bestBy: day, source: .manual, addedOn: day)
        await library.upsert(item)
        let plan = MealPlan(startDate: day, days: 7, constraintsSnapshot: "abc", solverVersion: "1", seed: 42, status: .active)
        let meal = PlannedMeal(planID: plan.id, date: day, slot: .dinner, recipeID: recipe.id, servings: 2, reasonCodes: [])
        await library.save(plan, meals: [meal])
        let expected = LarderExport(
            formatVersion: 1, exportedAt: day, profile: sampleProfile, constraints: constraints, targets: targets,
            recipes: [.init(recipe: recipe, ingredients: [ingredient])], pantry: [item],
            plans: [.init(plan: plan, meals: [meal])]
        )
        return (profiles, library, expected)
    }

    private func builder(_ profiles: FakeProfileRepository, _ library: FakeLibrary) -> ExportBuilder {
        ExportBuilder(profiles: profiles, recipes: library, pantry: library, plans: library)
    }

    @Test func exportDecodesBackIntoTheSameValues() async throws {
        let (profiles, library, expected) = await populated()
        let data = try await builder(profiles, library).build(exportedAt: day)
        let decoded = try ExportBuilder.decoder.decode(LarderExport.self, from: data)
        #expect(decoded == expected)
    }

    @Test func datesAreWrittenAsISO8601() async throws {
        let (profiles, library, _) = await populated()
        let data = try await builder(profiles, library).build(exportedAt: day)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"exportedAt\" : \"2026-10-16T00:00:00.000Z\""))
    }

    @Test func millisecondsSurvive() async throws {
        let exportedAt = day.addingTimeInterval(0.25)
        let data = try await builder(FakeProfileRepository(), FakeLibrary()).build(exportedAt: exportedAt)
        let decoded = try ExportBuilder.decoder.decode(LarderExport.self, from: data)
        #expect(decoded.exportedAt == exportedAt)
    }

    @Test func emptyStoreExportsAnEmptyDocument() async throws {
        let data = try await builder(FakeProfileRepository(), FakeLibrary()).build(exportedAt: day)
        let decoded = try ExportBuilder.decoder.decode(LarderExport.self, from: data)
        #expect(decoded.profile == nil)
        #expect(decoded.constraints.isEmpty && decoded.recipes.isEmpty && decoded.pantry.isEmpty && decoded.plans.isEmpty)
        #expect(decoded.formatVersion == LarderExport.currentFormatVersion)
    }

    @Test func repositoryFailureFailsTheExport() async {
        let (profiles, library, _) = await populated()
        await library.setFailsReads(true)
        await #expect(throws: FakeError.self) {
            try await builder(profiles, library).build(exportedAt: day)
        }
    }

    @Test func profileReadFailureFailsTheExport() async {
        let (profiles, library, _) = await populated()
        await profiles.setFailsReads(true)
        await #expect(throws: FakeError.self) {
            try await builder(profiles, library).build(exportedAt: day)
        }
    }
}
