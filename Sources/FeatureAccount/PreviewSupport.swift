#if DEBUG
import Foundation
import LarderCore
import Synchronization

/// In-memory stand-ins so previews render without a database or the App Store.
nonisolated enum PreviewSupport {
    actor Store: ProfileRepository, RecipeRepository, PantryRepository, PlanRepository {
        private var storedProfile: UserProfile?
        private var storedConstraints: [DietaryConstraint]
        private var storedTargets: [NutrientTarget] = []

        init(profile: UserProfile? = nil, constraints: [DietaryConstraint] = []) {
            storedProfile = profile
            storedConstraints = constraints
        }

        func profile() -> UserProfile? { storedProfile }
        func save(_ profile: UserProfile) { storedProfile = profile }
        func constraints() -> [DietaryConstraint] { storedConstraints }
        func saveConstraints(_ constraints: [DietaryConstraint]) { storedConstraints = constraints }
        func targets() -> [NutrientTarget] { storedTargets }
        func saveTargets(_ targets: [NutrientTarget]) { storedTargets = targets }

        func all() -> [Recipe] { [] }
        func search(text: String, limit: Int) -> [Recipe] { [] }
        func recipe(by id: RecipeID) -> Recipe? { nil }
        func save(_ recipe: Recipe, ingredients: [Ingredient]) {}
        func delete(_ id: RecipeID) {}
        func ingredients(for recipeID: RecipeID) -> [Ingredient] { [] }

        func items() -> [PantryItem] { [] }
        func upsert(_ item: PantryItem) {}
        func remove(_ id: PantryItemID) {}
        func consume(foodID: FoodID, grams: Double) {}

        func currentPlan() -> MealPlan? { nil }
        func plans() -> [MealPlan] { [] }
        func save(_ plan: MealPlan, meals: [PlannedMeal]) {}
        func meals(for planID: MealPlanID) -> [PlannedMeal] { [] }
        func updateMeal(_ meal: PlannedMeal) {}
    }

    struct Dates: DateProvider {
        var now: Date { Date() }
    }

    final class Flags: KeyValueStore {
        private let values = Mutex<[String: Bool]>([:])

        func bool(forKey key: String) -> Bool? { values.withLock { $0[key] } }
        func set(_ value: Bool, forKey key: String) { values.withLock { $0[key] = value } }
    }

    struct Shop: StoreFront {
        var products: [StoreProduct] = [
            StoreProduct(
                id: EntitlementStore.plusProductIDs[0], displayName: "Larder Plus Monthly",
                displayPrice: "$7.99", price: 7.99, period: BillingPeriod(value: 1, unit: .month)
            ),
            StoreProduct(
                id: EntitlementStore.plusProductIDs[1], displayName: "Larder Plus Annual",
                displayPrice: "$49.99", price: 49.99, period: BillingPeriod(value: 1, unit: .year),
                freeTrial: BillingPeriod(value: 7, unit: .day)
            ),
        ]
        var entitlements: [EntitlementRecord] = []

        func products(for ids: [String]) -> [StoreProduct] { products }
        func purchase(_ product: StoreProduct) -> PurchaseOutcome { .userCancelled }
        func currentEntitlements() -> [EntitlementRecord] { entitlements }
        var updates: AsyncStream<EntitlementRecord> { AsyncStream { $0.finish() } }
        func restore() {}
    }

    static let profile = UserProfile(
        birthYear: 1988, heightCm: 170, activityLevel: .light, goal: .lessWaste,
        householdSize: 3, currencyCode: "USD", maxCookMinutes: 35, equipment: [.oven, .stovetop]
    )

    static let constraints: [DietaryConstraint] = [
        .userSet(.allergen(.peanut), at: Date()),
        .userSet(.diet(.vegetarian), at: Date()),
        .userSet(.dislike(.name("Coriander")), at: Date()),
    ]

    @MainActor
    static func settingsModel() -> SettingsModel {
        let store = Store(profile: profile, constraints: constraints)
        return SettingsModel(
            profiles: store,
            exporter: ExportBuilder(profiles: store, recipes: store, pantry: store, plans: store),
            preferences: ComfortPreferences(store: Flags()),
            dates: Dates(),
            deleteAllData: {}
        )
    }

    @MainActor
    static func entitlements(plusUntil expiry: Date? = nil) -> EntitlementStore {
        let records = expiry.map {
            [EntitlementRecord(productID: EntitlementStore.plusProductIDs[1], expirationDate: $0, isVerified: true, signedJWS: nil)]
        } ?? []
        return EntitlementStore(storeFront: Shop(entitlements: records), dates: Dates())
    }
}
#endif
