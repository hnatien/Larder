import LarderCore
import LarderDesign
import SwiftUI

/// The Groceries tab: what to buy by aisle in store-walk order, an add field, and the bought items folded away.
public struct GroceryView: View {
    private let model: GroceryModel
    private let onOpenPlan: (() -> Void)?
    private let onOpenSettings: (() -> Void)?
    @State private var basketExpanded = false

    /// Creates the grocery tab; `onOpenPlan` is offered when the list is empty, and `onOpenSettings` adds the
    /// Settings button.
    public init(model: GroceryModel, onOpenPlan: (() -> Void)? = nil, onOpenSettings: (() -> Void)? = nil) {
        self.model = model
        self.onOpenPlan = onOpenPlan
        self.onOpenSettings = onOpenSettings
    }

    private var toBuyCount: Int { model.toBuy.map(\.entries.count).reduce(0, +) }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    AddItemField { name in Task { await model.addManual(name: name) } }
                } footer: {
                    if !model.isEmpty {
                        Text(GroceryCopy.tickHint)
                            .font(LarderFont.body(.footnote))
                            .foregroundStyle(LarderColor.ink.secondary)
                    }
                }
                .listRowBackground(LarderColor.surface.raised)
                if let error = model.error {
                    InlineBanner(
                        GroceryCopy.message(for: error),
                        action: error == .loadFailed ? .init(title: GroceryCopy.tryAgain) { Task { await model.load() } } : nil
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if model.isEmpty && !model.isLoading {
                    EmptyShelf(
                        title: GroceryCopy.emptyTitle,
                        message: GroceryCopy.emptyMessage,
                        illustration: .groceries,
                        systemImage: "cart",
                        action: onOpenPlan.map { .init(title: GroceryCopy.openPlan, perform: $0) }
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(model.toBuy) { section in
                    Section {
                        header(GroceryCopy.name(of: section.aisle), count: section.entries.count)
                            .listRowBackground(LarderColor.surface.raised)
                        ForEach(section.entries) { row($0) }
                    }
                }
                if !model.basket.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $basketExpanded) {
                            ForEach(model.basket.flatMap(\.entries)) { row($0) }
                            Button(GroceryCopy.clearBasket, systemImage: "trash") { Task { await model.clearChecked() } }
                                .foregroundStyle(LarderColor.accent.brand)
                                .frame(minHeight: 44)
                        } label: {
                            header(GroceryCopy.inTheBasket, count: model.basket.map(\.entries.count).reduce(0, +))
                        }
                        .tint(LarderColor.ink.primary)
                    }
                    .listRowBackground(LarderColor.surface.raised)
                }
            }
            .larderGroupedList()
            .navigationTitle(Copy.Tab.grocery)
            .navigationSubtitle(GroceryCopy.subtitle(toBuy: toBuyCount))
            .settingsButton(onOpenSettings)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: model.shareText()) {
                        Label(GroceryCopy.share, systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.toBuy.isEmpty)
                }
            }
            .refreshable { await model.load() }
            .task { await model.load() }
            .sensoryFeedback(.selection, trigger: model.checked)
            .larderToast(toast, onExpire: model.dismissNotice)
        }
    }

    /// The last tick that landed food, or the last removal, with Undo.
    private var toast: LarderToast? {
        model.notice.map { notice in
            let symbol = if case .landed = notice.kind { "refrigerator.fill" } else { "trash.circle.fill" }
            return LarderToast(id: notice.id, GroceryCopy.notice(notice.kind), systemImage: symbol, actionTitle: GroceryCopy.undo) {
                Task { await model.undoNotice() }
            }
        }
    }

    private func header(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(LarderFont.body(.headline, weight: .semibold))
                .foregroundStyle(LarderColor.ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text(count, format: .number)
                .font(LarderFont.body(.subheadline, weight: .semibold))
                .foregroundStyle(LarderColor.ink.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ entry: GroceryEntry) -> some View {
        GroceryRowView(
            name: entry.name,
            quantity: model.quantityText(entry),
            source: model.sourceText(entry),
            partiallyInPantry: entry.partiallyInPantry,
            isChecked: model.checked.contains(entry.key)
        ) {
            Task { await model.toggle(entry) }
        }
        .listRowBackground(LarderColor.surface.raised)
        .listRowSeparatorTint(LarderColor.line.hairline)
        .swipeActions(edge: .trailing) {
            if case .manual(let item) = entry {
                Button(GroceryCopy.delete, systemImage: "trash", role: .destructive) { Task { await model.removeManual(item) } }
            }
        }
        .contextMenu {
            if case .manual(let item) = entry {
                Button(GroceryCopy.delete, systemImage: "trash", role: .destructive) { Task { await model.removeManual(item) } }
            }
        }
        .accessibilityActions {
            if case .manual(let item) = entry {
                Button(GroceryCopy.delete) { Task { await model.removeManual(item) } }
            }
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
    func food(byGTIN gtin: String) async throws -> Food? { nil }
    func upsert(_ foods: [Food]) async throws {}
    func items() async throws -> [PantryItem] { [] }
    func upsert(_ item: PantryItem) async throws {}
    func remove(_ id: PantryItemID) async throws {}
    func consume(foodID: FoodID, grams: Double) async throws -> [PantryItem] { [] }
    func record(_ events: [PantryEvent]) async throws {}
    func removeEvents(_ ids: [PantryEventID]) async throws {}
    func events(from start: Date, to end: Date) async throws -> [PantryEvent] { [] }
}

/// Hand-written items for previews; nothing else is kept.
private actor PreviewBasket: GroceryBasketRepository {
    private var items: [ManualItem]

    init(manual: [String]) {
        items = manual.map { ManualItem(name: $0, quantity: "2") }
    }

    func manualItems() -> [ManualItem] { items }
    func saveManualItem(_ item: ManualItem) { items.append(item) }
    func removeManualItem(_ id: ManualItemID) { items.removeAll { $0.id == id } }
    func basketLines() -> [BasketLine] { [] }
    func saveBasketLine(_ line: BasketLine) {}
    func removeBasketLine(_ key: GroceryItemKey) {}
    func clearBasket() {}
}

@MainActor private func previewModel(manual: [String]) -> GroceryModel {
    let store = PreviewStore()
    return GroceryModel(plans: store, recipes: store, foods: store, pantry: store, basket: PreviewBasket(manual: manual), dates: store)
}

#Preview("GroceryView") {
    GroceryView(model: previewModel(manual: ["Lemons", "Oat milk"]))
}

#Preview("GroceryView empty") {
    GroceryView(model: previewModel(manual: []))
}
#endif
