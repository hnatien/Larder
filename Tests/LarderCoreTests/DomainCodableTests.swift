import Foundation
import Testing
@testable import LarderCore

struct DomainCodableTests {
    @Test func foodRoundTrips() throws {
        let food = Food(
            name: "Chickpeas, canned, drained",
            source: .srLegacy,
            fdcID: 173757,
            gtin: "0012345678905",
            nutrientsPer100g: Nutrients(energyKcal: 139, proteinG: 7.05, fiberG: 7.6, sodiumMg: 246),
            portions: [Portion(label: "1 cup", grams: 152)],
            foodGroup: .legumes,
            allergens: AllergenTags([.sesame: .verifiedFree, .wheat: .mayContain])
        )
        #expect(try Fixtures.roundTrip(food) == food)
    }

    @Test func missingNutrientsStayUnknownAfterRoundTrip() throws {
        let decoded = try Fixtures.roundTrip(Nutrients(proteinG: 0))
        #expect(decoded.proteinG == 0)
        #expect(decoded.addedSugarG == nil)
    }

    @Test func recipeRoundTrips() throws {
        let recipe = Recipe(
            title: "Rice and greens",
            origin: .userImport,
            sourceURL: URL(string: "https://example.com/rice"),
            license: "personal use",
            servings: 2,
            prepMinutes: 10,
            cookMinutes: 15,
            steps: [RecipeStep(text: "Rinse the rice."), RecipeStep(text: "Simmer.", timerSeconds: 900)],
            tags: RecipeTags(
                cuisine: "Korean",
                mealTypes: [.lunch, .dinner],
                equipment: [.stovetop],
                dietFlags: [.vegan]
            )
        )
        #expect(try Fixtures.roundTrip(recipe) == recipe)
    }

    @Test func ingredientRoundTrips() throws {
        let ingredient = Ingredient(
            recipeID: RecipeID(),
            rawText: "2 cloves garlic, minced",
            quantity: 2,
            unit: .clove,
            foodID: FoodID(),
            gramsResolved: 6,
            matchConfidence: 0.92,
            isGarnish: true
        )
        #expect(try Fixtures.roundTrip(ingredient) == ingredient)
    }

    @Test func pantryItemRoundTrips() throws {
        let item = PantryItem(
            foodID: FoodID(),
            rawName: "spinach",
            quantityGrams: 180,
            location: .fridge,
            bestBy: Fixtures.date(2026, 10, 19),
            source: .naturalLanguage,
            addedOn: Fixtures.date(2026, 10, 16)
        )
        #expect(try Fixtures.roundTrip(item) == item)
    }

    @Test func pantryItemWithoutFoodOrDateRoundTrips() throws {
        let item = PantryItem(
            rawName: "mystery jar",
            quantityGrams: 0,
            location: .other,
            source: .manual,
            addedOn: Fixtures.date(2026, 1, 1)
        )
        let decoded = try Fixtures.roundTrip(item)
        #expect(decoded == item)
        #expect(decoded.foodID == nil)
        #expect(decoded.bestBy == nil)
    }

    @Test func fixturesCoverEveryConstraintKind() {
        #expect(Set(Fixtures.allConstraintKinds.map(Fixtures.caseName)).count == 7)
    }

    @Test(arguments: Fixtures.allConstraintKinds)
    func dietaryConstraintRoundTrips(kind: ConstraintKind) throws {
        let constraint = DietaryConstraint(
            axis: .medical,
            kind: kind,
            strictness: .hard,
            source: .clinician,
            lastConfirmed: Fixtures.date(2026, 9, 1)
        )
        #expect(try Fixtures.roundTrip(constraint) == constraint)
    }

    @Test func fixturesCoverEveryReasonCode() {
        #expect(Set(Fixtures.allReasonCodes.map(Fixtures.caseName)).count == 9)
    }

    @Test(arguments: Fixtures.allReasonCodes)
    func reasonCodeRoundTrips(code: ReasonCode) throws {
        #expect(try Fixtures.roundTrip(code) == code)
    }

    @Test func plannedMealRoundTripsWithEveryReasonCode() throws {
        let meal = PlannedMeal(
            planID: MealPlanID(),
            date: Fixtures.date(2026, 10, 20),
            slot: .dinner,
            recipeID: RecipeID(),
            servings: 3,
            leftoverOf: PlannedMealID(),
            isLocked: true,
            status: .cooked,
            reasonCodes: Fixtures.allReasonCodes,
            swapHistory: [RecipeID(), RecipeID()]
        )
        #expect(try Fixtures.roundTrip(meal) == meal)
    }

    @Test func mealPlanRoundTripsFullWidthSeed() throws {
        let plan = MealPlan(
            startDate: Fixtures.date(2026, 10, 19),
            days: 7,
            constraintsSnapshot: "a1b2c3",
            solverVersion: "1.0.0",
            seed: .max,
            status: .active
        )
        #expect(try Fixtures.roundTrip(plan) == plan)
    }

    @Test func userProfileDefaultsKeepNumbersAndConsentsOff() throws {
        let profile = UserProfile(
            birthYear: 1990,
            heightCm: 170,
            activityLevel: .moderate,
            goal: .lessWaste,
            householdSize: 2,
            weeklyBudget: Decimal(string: "85.50"),
            currencyCode: "USD",
            maxCookMinutes: 30
        )
        #expect(profile.showsNumbers == false)
        #expect(profile.consents == Consents(aiProcessing: false, cloudSync: false))
        #expect(profile.sex == .unspecified)
        #expect(try Fixtures.roundTrip(profile) == profile)
    }

    @Test func nutrientTargetRoundTrips() throws {
        let target = NutrientTarget(nutrient: .sodium, basis: .perDay, max: 2300, priority: 2, source: .dga2025)
        #expect(try Fixtures.roundTrip(target) == target)
    }

    @Test func identifierEncodesAsBareUUIDString() throws {
        let id = FoodID()
        let json = String(decoding: try JSONEncoder().encode([id]), as: UTF8.self)
        #expect(json == #"["\#(id.rawValue.uuidString)"]"#)
    }

    @Test func identifierDecodingRejectsNonUUID() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([RecipeID].self, from: Data(#"["not-a-uuid"]"#.utf8))
        }
    }

    @Test func decodingUnknownEnumValueFails() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([FoodSource].self, from: Data(#"["madeUp"]"#.utf8))
        }
    }
}
