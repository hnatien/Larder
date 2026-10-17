import LarderCore
import LarderDesign
import SwiftUI

/// Puts a recipe on a day's dinner and reports whether it worked.
public typealias AddToPlan = (Recipe, Date) async -> Bool

/// What finishing a recipe changed, offered back as a toast with Undo.
public struct CookingUndo: Identifiable {
    public let id = UUID()
    public let message: String
    /// Takes the cooking back.
    public let undo: @MainActor () async -> Void
    /// Lets the cooking stand once the toast has gone.
    public let dismiss: @MainActor () -> Void

    /// Creates an undo.
    public init(message: String, undo: @escaping @MainActor () async -> Void, dismiss: @escaping @MainActor () -> Void) {
        self.message = message
        self.undo = undo
        self.dismiss = dismiss
    }
}

/// Records that the cook finished a recipe at the given servings; returns the undo, or `nil` when nothing was recorded.
public typealias FinishCooking = (Recipe, Int) async -> CookingUndo?

/// Puts ingredient lines on the grocery list and reports whether it worked.
public typealias AddToGroceries = ([Ingredient]) async -> Bool

/// The dinners already planned, by the start of their day, so Add to plan can say what a day would replace.
public typealias PlannedDinners = () async -> [Date: String]

/// The Recipes tab: a searchable, filterable library; + imports a recipe from the web.
public struct RecipesView: View {
    @Bindable private var model: RecipesModel
    private let onAddToPlan: AddToPlan?
    private let onFinishCooking: FinishCooking?
    private let onAddToGroceries: AddToGroceries?
    private let plannedDinners: PlannedDinners?
    private let onOpenSettings: (() -> Void)?
    @State private var importModel: ImportModel?
    @State private var showsHidden = false

    /// Creates the tab root; `onAddToPlan`, `plannedDinners` and `onAddToGroceries` are offered on each recipe's
    /// detail, `onFinishCooking` runs when cooking mode's Finish is tapped, and `onOpenSettings` adds the Settings
    /// button.
    public init(
        model: RecipesModel,
        onAddToPlan: AddToPlan? = nil,
        onFinishCooking: FinishCooking? = nil,
        onAddToGroceries: AddToGroceries? = nil,
        plannedDinners: PlannedDinners? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.model = model
        self.onAddToPlan = onAddToPlan
        self.onFinishCooking = onFinishCooking
        self.onAddToGroceries = onAddToGroceries
        self.plannedDinners = plannedDinners
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LarderColor.surface.canvas)
                .navigationTitle(Copy.Tab.recipes)
                .navigationSubtitle(RecipesCopy.subtitle)
                .navigationDestination(for: Recipe.self) { recipe in
                    RecipeDetailView(
                        model: model,
                        recipe: recipe,
                        onAddToPlan: onAddToPlan,
                        onFinishCooking: onFinishCooking,
                        onAddToGroceries: onAddToGroceries,
                        plannedDinners: plannedDinners
                    )
                }
                .searchable(text: $model.query, prompt: RecipesCopy.searchPrompt)
                .task(id: model.query) { await model.search() }
                .refreshable { await model.load() }
                .onChange(of: model.results.count) { _, count in
                    guard !model.query.isEmpty else { return }
                    AccessibilityNotification.Announcement(RecipesCopy.resultCount(count)).post()
                }
                .settingsButton(onOpenSettings)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(RecipesCopy.importRecipe, systemImage: "plus") {
                            importModel = model.makeImportModel()
                        }
                        .disabled(!model.hasLoaded)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker(RecipesCopy.sortTitle, selection: $model.sort) {
                                ForEach(RecipeSort.allCases, id: \.self) { Text(RecipesCopy.name(of: $0)).tag($0) }
                            }
                            if !model.hiddenRecipes.isEmpty {
                                Button(RecipesCopy.hiddenTitle, systemImage: "eye.slash") { showsHidden = true }
                            }
                        } label: {
                            Label(RecipesCopy.sortTitle, systemImage: "arrow.up.arrow.down")
                        }
                        .disabled(!model.hasLoaded)
                    }
                }
                .sheet(isPresented: $showsHidden) {
                    HiddenRecipesSheet(model: model)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
                .sheet(item: $importModel) { importModel in
                    ImportSheet(model: importModel)
                        .presentationDragIndicator(.visible)
                }
                .alert(
                    RecipesCopy.message(for: model.error ?? .loadFailed),
                    isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.dismissError() } })
                ) {
                    Button(RecipesCopy.ok) { model.dismissError() }
                }
        }
    }

    @ViewBuilder private var content: some View {
        if !model.hasLoaded {
            ProgressView(RecipesCopy.loading)
        } else if model.recipes.isEmpty {
            ScrollView {
                EmptyShelf(
                    title: RecipesCopy.emptyLibraryTitle,
                    message: RecipesCopy.emptyLibraryMessage,
                    illustration: .recipes,
                    systemImage: "book",
                    action: EmptyShelf.Action(title: RecipesCopy.importRecipe) {
                        importModel = model.makeImportModel()
                    }
                )
                .padding(LarderSpacing.l)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: LarderSpacing.m) {
                    FilterChips(model: model)
                        .padding(.top, LarderSpacing.s)
                    if model.results.isEmpty {
                        EmptyShelf(
                            title: RecipesCopy.noResultsTitle,
                            message: RecipesCopy.noResultsMessage,
                            systemImage: "magnifyingglass",
                            action: model.filters.isEmpty
                                ? nil
                                : EmptyShelf.Action(title: RecipesCopy.clearFilters) { model.filters = RecipeFilters() }
                        )
                        .padding(LarderSpacing.l)
                    } else {
                        PaperCard(padded: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(model.results.enumerated()), id: \.element.id) { index, recipe in
                                    if index > 0 {
                                        Divider()
                                            .overlay(LarderColor.line.hairline)
                                            .padding(.leading, LarderSpacing.l + 56 + LarderSpacing.m)
                                    }
                                    NavigationLink(value: recipe) {
                                        RecipeRow(
                                            recipe: recipe,
                                            isFavourite: model.favourites.contains(recipe.id),
                                            coverage: model.coverage[recipe.id]
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, LarderSpacing.l)
                    }
                }
                .padding(.bottom, LarderSpacing.xl)
            }
        }
    }
}

/// The recipes hidden from the library, each with Show again.
private struct HiddenRecipesSheet: View {
    let model: RecipesModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Text(RecipesCopy.hiddenHint)
                    .font(LarderFont.body(.subheadline))
                    .foregroundStyle(LarderColor.ink.secondary)
                    .listRowBackground(Color.clear)
                if model.hiddenRecipes.isEmpty {
                    Text(RecipesCopy.hiddenEmpty)
                        .font(LarderFont.body(.body))
                        .foregroundStyle(LarderColor.ink.secondary)
                        .listRowBackground(LarderColor.surface.raised)
                }
                ForEach(model.hiddenRecipes) { recipe in
                    AdaptiveStack(spacing: LarderSpacing.m, stacksFrom: .accessibility1) {
                        Text(recipe.title)
                            .font(LarderFont.body(.body, weight: .semibold))
                            .foregroundStyle(LarderColor.ink.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(RecipesCopy.showAgain) { Task { await model.unhide(recipe) } }
                            .buttonStyle(.larderSecondary)
                            .accessibilityLabel(RecipesCopy.showAgainNamed(recipe.title))
                    }
                    .listRowBackground(LarderColor.surface.raised)
                }
            }
            .larderGroupedList()
            .navigationTitle(RecipesCopy.hiddenTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(RecipesCopy.done) { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
#Preview("RecipesView") {
    RecipesView(model: PreviewData.model())
}

#Preview("RecipesView empty") {
    let store = PreviewStore(recipes: [], ingredients: [:])
    RecipesView(model: RecipesModel(
        recipes: store, photos: store, foods: store, profile: store, pantry: store, marks: store,
        assistant: PreviewAssistant(), isPlus: { false }
    ))
}
#endif
