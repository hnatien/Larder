import LarderCore
import LarderDesign
import SwiftUI

/// The few filters people reach for most, as chips that wrap instead of scrolling off the edge, then a Filters button
/// that opens every filter grouped by kind. Selection shows by a check as well as colour.
struct FilterChips: View {
    @Bindable var model: RecipesModel
    @State private var showsAllFilters = false

    /// Filters the sheet holds that are on but have no chip here, so the Filters button can count them.
    private var hiddenActiveCount: Int {
        var shown = RecipeFilters()
        shown.favouritesOnly = model.filters.favouritesOnly
        shown.maxMinutes = model.filters.maxMinutes == Self.quickMinutes ? Self.quickMinutes : nil
        shown.mealTypes = model.filters.mealTypes.intersection([.dinner])
        shown.dietFlags = model.filters.dietFlags.intersection([.vegetarian])
        return model.filters.activeCount - shown.activeCount
    }

    /// The minutes the quick chip allows.
    static let quickMinutes = 30

    var body: some View {
        ChipFlow {
            ChoiceChip(RecipesCopy.favourites, systemImage: "heart", isSelected: model.filters.favouritesOnly) {
                model.filters.favouritesOnly.toggle()
            }
            ChoiceChip(RecipesCopy.quickFilter, systemImage: "bolt", isSelected: model.filters.maxMinutes == Self.quickMinutes) {
                model.filters.maxMinutes = model.filters.maxMinutes == Self.quickMinutes ? nil : Self.quickMinutes
            }
            ChoiceChip(RecipesCopy.name(of: MealType.dinner), isSelected: model.filters.mealTypes.contains(.dinner)) {
                model.filters.mealTypes.formSymmetricDifference([.dinner])
            }
            ChoiceChip(RecipesCopy.name(of: DietPattern.vegetarian), isSelected: model.filters.dietFlags.contains(.vegetarian)) {
                model.filters.dietFlags.formSymmetricDifference([.vegetarian])
            }
            ChoiceChip(
                hiddenActiveCount == 0 ? RecipesCopy.moreFilters : RecipesCopy.moreFilters(hiddenActiveCount),
                systemImage: "line.3.horizontal.decrease",
                isSelected: hiddenActiveCount > 0
            ) {
                showsAllFilters = true
            }
        }
        .padding(.horizontal, LarderSpacing.l)
        .sheet(isPresented: $showsAllFilters) {
            FiltersSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Every filter, grouped: meal, diet, time and cuisine, with Clear all.
private struct FiltersSheet: View {
    @Bindable var model: RecipesModel
    @Environment(\.dismiss) private var dismiss

    /// The time limits offered, in minutes; `nil` is any time.
    private static let timeLimits: [Int?] = [nil, 20, 30, 45, 60]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LarderSpacing.xl) {
                    group(RecipesCopy.mealFilter) {
                        ForEach(MealType.allCases, id: \.self) { mealType in
                            ChoiceChip(RecipesCopy.name(of: mealType), isSelected: model.filters.mealTypes.contains(mealType)) {
                                model.filters.mealTypes.formSymmetricDifference([mealType])
                            }
                        }
                    }
                    group(RecipesCopy.dietFilter) {
                        ForEach(DietPattern.allCases, id: \.self) { diet in
                            ChoiceChip(RecipesCopy.name(of: diet), isSelected: model.filters.dietFlags.contains(diet)) {
                                model.filters.dietFlags.formSymmetricDifference([diet])
                            }
                        }
                    }
                    group(RecipesCopy.timeFilter) {
                        ForEach(Self.timeLimits, id: \.self) { limit in
                            ChoiceChip(RecipesCopy.timeLimit(limit), isSelected: model.filters.maxMinutes == limit) {
                                model.filters.maxMinutes = limit
                            }
                        }
                    }
                    if !model.cuisines.isEmpty {
                        group(RecipesCopy.cuisine) {
                            ChoiceChip(RecipesCopy.anyCuisine, isSelected: model.filters.cuisine == nil) {
                                model.filters.cuisine = nil
                            }
                            ForEach(model.cuisines, id: \.self) { cuisine in
                                ChoiceChip(cuisine, isSelected: model.filters.cuisine == cuisine) {
                                    model.filters.cuisine = model.filters.cuisine == cuisine ? nil : cuisine
                                }
                            }
                        }
                    }
                }
                .padding(LarderSpacing.l)
            }
            .background(LarderColor.surface.canvas)
            .navigationTitle(RecipesCopy.filtersTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(RecipesCopy.clearFilters) { model.filters = RecipeFilters() }
                        .disabled(model.filters.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(RecipesCopy.showResults(model.results.count)) { dismiss() }
                }
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            Text(title)
                .font(LarderFont.body(.headline, weight: .semibold))
                .foregroundStyle(LarderColor.ink.primary)
                .accessibilityAddTraits(.isHeader)
            ChipFlow { content() }
        }
    }
}

#if DEBUG
#Preview("FilterChips") {
    FilterChips(model: PreviewData.model())
        .padding(.vertical, LarderSpacing.l)
        .background(LarderColor.surface.canvas)
}
#endif
