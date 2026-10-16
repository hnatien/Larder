import LarderCore
import LarderDesign
import SwiftUI

/// The Recipes tab: a searchable, filterable library with an import action.
public struct RecipesView: View {
    @Bindable private var model: RecipesModel
    private let onAddToPlan: ((Recipe) -> Void)?
    @State private var importModel: ImportModel?

    /// Creates the tab root; `onAddToPlan` is called from a recipe's detail when the user adds it to the Ledger.
    public init(model: RecipesModel, onAddToPlan: ((Recipe) -> Void)? = nil) {
        self.model = model
        self.onAddToPlan = onAddToPlan
    }

    public var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LarderColor.surface.canvas)
                .navigationTitle(Copy.Tab.recipes)
                .navigationDestination(for: Recipe.self) { recipe in
                    RecipeDetailView(model: model, recipe: recipe, onAddToPlan: onAddToPlan)
                }
                .searchable(text: $model.query, prompt: RecipesCopy.searchPrompt)
                .task(id: model.query) { await model.search() }
                .refreshable { await model.load() }
                .onChange(of: model.results.count) { _, count in
                    guard !model.query.isEmpty else { return }
                    AccessibilityNotification.Announcement(RecipesCopy.resultCount(count)).post()
                }
                .safeAreaInset(edge: .bottom, alignment: .trailing) {
                    if model.hasLoaded {
                        FloatingAction(RecipesCopy.importRecipe, systemImage: "plus") {
                            importModel = model.makeImportModel()
                        }
                        .padding(.horizontal, LarderSpacing.l)
                        .padding(.bottom, LarderSpacing.s)
                    }
                }
                .sheet(item: $importModel) { importModel in
                    ImportSheet(model: importModel)
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
            EmptyShelf(
                title: RecipesCopy.emptyLibraryTitle,
                message: RecipesCopy.emptyLibraryMessage,
                action: EmptyShelf.Action(title: RecipesCopy.importRecipe) {
                    importModel = model.makeImportModel()
                }
            )
            .padding(LarderSpacing.l)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: LarderSpacing.m) {
                    FilterChips(model: model)
                    if model.results.isEmpty {
                        EmptyShelf(
                            title: RecipesCopy.noResultsTitle,
                            message: RecipesCopy.noResultsMessage,
                            action: model.filters.isEmpty
                                ? nil
                                : EmptyShelf.Action(title: RecipesCopy.clearFilters) { model.filters = RecipeFilters() }
                        )
                        .padding(LarderSpacing.l)
                    } else {
                        // Ledger rows on the canvas, a hairline under each, as on the Shelves and Ledger tabs.
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(model.results) { recipe in
                                NavigationLink(value: recipe) {
                                    RecipeRow(recipe: recipe)
                                }
                                .buttonStyle(.plain)
                                Divider().overlay(LarderColor.line.hairline)
                            }
                        }
                        .padding(.horizontal, LarderSpacing.l)
                    }
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
    RecipesView(model: RecipesModel(recipes: store, foods: store, profile: store, assistant: PreviewAssistant(), isPlus: { false }))
}
#endif
