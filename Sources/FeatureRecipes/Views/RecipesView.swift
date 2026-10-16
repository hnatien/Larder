import LarderCore
import LarderDesign
import SwiftUI

/// Puts a recipe on a day's dinner and reports whether it worked.
public typealias AddToPlan = (Recipe, Date) async -> Bool

/// The Recipes tab: a searchable, filterable library; + imports a recipe from the web.
public struct RecipesView: View {
    @Bindable private var model: RecipesModel
    private let onAddToPlan: AddToPlan?
    private let onOpenSettings: (() -> Void)?
    @State private var importModel: ImportModel?

    /// Creates the tab root; `onAddToPlan` is offered on each recipe's detail, and `onOpenSettings` adds the
    /// Settings button.
    public init(model: RecipesModel, onAddToPlan: AddToPlan? = nil, onOpenSettings: (() -> Void)? = nil) {
        self.model = model
        self.onAddToPlan = onAddToPlan
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
                    RecipeDetailView(model: model, recipe: recipe, onAddToPlan: onAddToPlan)
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
                                        RecipeRow(recipe: recipe)
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

#if DEBUG
#Preview("RecipesView") {
    RecipesView(model: PreviewData.model())
}

#Preview("RecipesView empty") {
    let store = PreviewStore(recipes: [], ingredients: [:])
    RecipesView(model: RecipesModel(recipes: store, photos: store, foods: store, profile: store, assistant: PreviewAssistant(), isPlus: { false }))
}
#endif
