import LarderCore
import LarderDesign
import SwiftUI

/// The grocery tab: the list by aisle in store-walk order, a basket of bought items and a field for adding by hand.
public struct GroceryView: View {
    private let model: GroceryModel
    @State private var basketExpanded = false

    /// Creates the grocery tab over a model.
    public init(model: GroceryModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LarderSpacing.xl) {
                    AddItemField { model.addManual(name: $0) }
                    if let error = model.error {
                        Text(GroceryCopy.message(for: error))
                            .font(LarderFont.body(.body))
                            .foregroundStyle(LarderColor.status(.warning))
                    }
                    if model.isEmpty && !model.isLoading {
                        EmptyShelf(
                            title: GroceryCopy.emptyTitle,
                            message: GroceryCopy.emptyMessage
                        )
                    }
                    ForEach(model.toBuy) { section in
                        aisleSection(section)
                    }
                    if !model.basket.isEmpty {
                        basketSection
                    }
                }
                .padding(LarderSpacing.l)
            }
            .background(LarderColor.surface.canvas)
            .navigationTitle(Copy.Tab.grocery)
            .toolbar {
                ToolbarItem {
                    ShareLink(item: model.shareText())
                        .disabled(model.toBuy.isEmpty)
                }
            }
            .task { await model.load() }
        }
    }

    private var basketSection: some View {
        DisclosureGroup(isExpanded: $basketExpanded) {
            VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                ForEach(model.basket.flatMap(\.entries)) { entry in
                    row(entry)
                }
                Button(GroceryCopy.clearBasket) { model.clearChecked() }
                    .buttonStyle(.larderQuiet)
            }
        } label: {
            SectionHeading(GroceryCopy.inTheBasket)
        }
        .tint(LarderColor.ink.primary)
    }

    private func aisleSection(_ section: GroceryEntrySection) -> some View {
        VStack(alignment: .leading, spacing: LarderSpacing.xs) {
            SectionHeading(GroceryCopy.name(of: section.aisle))
            ForEach(section.entries) { entry in
                row(entry)
            }
        }
    }

    private func row(_ entry: GroceryEntry) -> some View {
        GroceryRowView(
            name: entry.name,
            quantity: model.quantityText(entry),
            partiallyInPantry: entry.partiallyInPantry,
            isChecked: model.checked.contains(entry.key)
        ) {
            Task { await model.toggle(entry) }
        }
    }
}

#if DEBUG
private struct PreviewStore: PlanRepository, RecipeRepository, FoodRepository, PantryRepository, DateProvider {
    var now: Date { Date(timeIntervalSince1970: 0) }
    func currentPlan() async throws -> MealPlan? { nil }
    func plans() async throws -> [MealPlan] { [] }
    func save(_ plan: MealPlan, meals: [PlannedMeal]) async throws {}
    func meals(for planID: MealPlanID) async throws -> [PlannedMeal] { [] }
    func updateMeal(_ meal: PlannedMeal) async throws {}
    func all() async throws -> [Recipe] { [] }
    func search(text: String, limit: Int) async throws -> [Recipe] { [] }
    func recipe(by id: RecipeID) async throws -> Recipe? { nil }
    func save(_ recipe: Recipe, ingredients: [Ingredient]) async throws {}
    func delete(_ id: RecipeID) async throws {}
    func ingredients(for recipeID: RecipeID) async throws -> [Ingredient] { [] }
    func search(text: String, limit: Int) async throws -> [Food] { [] }
    func food(by id: FoodID) async throws -> Food? { nil }
    func foods(byIDs ids: [FoodID]) async throws -> [Food] { [] }
    func upsert(_ foods: [Food]) async throws {}
    func items() async throws -> [PantryItem] { [] }
    func upsert(_ item: PantryItem) async throws {}
    func remove(_ id: PantryItemID) async throws {}
    func consume(foodID: FoodID, grams: Double) async throws {}
}

@MainActor private func previewModel(manual: [String]) -> GroceryModel {
    let store = PreviewStore()
    let model = GroceryModel(plans: store, recipes: store, foods: store, pantry: store, dates: store)
    for name in manual { model.addManual(name: name, quantity: "2") }
    return model
}

#Preview("GroceryView") {
    GroceryView(model: previewModel(manual: ["Lemons", "Oat milk"]))
}

#Preview("GroceryView empty") {
    GroceryView(model: previewModel(manual: []))
}
#endif
