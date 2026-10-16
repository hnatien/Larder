import LarderCore
import LarderDesign
import SwiftUI

/// One scrolling row of filter chips: quick, meal types, diets, then a cuisine menu. Selection shows by a check as
/// well as colour.
struct FilterChips: View {
    @Bindable var model: RecipesModel
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LarderSpacing.s) {
                ChoiceChip(RecipesCopy.quickFilter, systemImage: "bolt", isSelected: model.filters.maxMinutes == 30) {
                    model.filters.maxMinutes = model.filters.maxMinutes == 30 ? nil : 30
                }
                ForEach(MealType.allCases, id: \.self) { mealType in
                    ChoiceChip(RecipesCopy.name(of: mealType), isSelected: model.filters.mealTypes.contains(mealType)) {
                        model.filters.mealTypes.formSymmetricDifference([mealType])
                    }
                }
                ForEach(DietPattern.allCases, id: \.self) { diet in
                    ChoiceChip(RecipesCopy.name(of: diet), isSelected: model.filters.dietFlags.contains(diet)) {
                        model.filters.dietFlags.formSymmetricDifference([diet])
                    }
                }
                if !model.cuisines.isEmpty {
                    cuisineMenu
                }
            }
            .padding(.horizontal, LarderSpacing.l)
            .padding(.vertical, LarderSpacing.xxs)
        }
    }

    private var cuisineMenu: some View {
        Menu {
            Picker(RecipesCopy.cuisine, selection: $model.filters.cuisine) {
                Text(RecipesCopy.anyCuisine).tag(String?.none)
                ForEach(model.cuisines, id: \.self) { Text($0).tag(String?.some($0)) }
            }
        } label: {
            HStack(spacing: LarderSpacing.xs) {
                Text(model.filters.cuisine ?? RecipesCopy.cuisine)
                Image(systemName: "chevron.down")
                    .font(LarderFont.body(.caption, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .font(LarderFont.body(.body, weight: model.filters.cuisine == nil ? .regular : .semibold))
            .foregroundStyle(model.filters.cuisine == nil ? LarderColor.ink.primary : LarderColor.ink.onAccent)
            .padding(.horizontal, LarderSpacing.l)
            .padding(.vertical, LarderSpacing.s + LarderSpacing.xxs)
            .frame(minHeight: 44)
            .background(model.filters.cuisine == nil ? LarderColor.surface.raised : LarderColor.accent.brand, in: Capsule())
            .overlay {
                if model.filters.cuisine == nil {
                    Capsule().strokeBorder(LarderColor.line.strong, lineWidth: 1 / displayScale)
                }
            }
        }
        .accessibilityLabel(RecipesCopy.cuisine)
        .accessibilityValue(model.filters.cuisine ?? RecipesCopy.anyCuisine)
    }
}

#if DEBUG
#Preview("FilterChips") {
    FilterChips(model: PreviewData.model())
        .padding(.vertical, LarderSpacing.l)
        .background(LarderColor.surface.canvas)
}
#endif
