import LarderCore
import LarderDesign
import SwiftUI

/// A row of toggle chips for meal type, diet, time and cuisine. Selection is shown by a checkmark as well as colour.
struct FilterChips: View {
    @Bindable var model: RecipesModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LarderSpacing.s) {
                ForEach(MealType.allCases, id: \.self) { mealType in
                    FilterChip(title: RecipesCopy.name(of: mealType), isOn: model.filters.mealTypes.contains(mealType)) {
                        model.filters.mealTypes.formSymmetricDifference([mealType])
                    }
                }
                ForEach(DietPattern.allCases, id: \.self) { diet in
                    FilterChip(title: RecipesCopy.name(of: diet), isOn: model.filters.dietFlags.contains(diet)) {
                        model.filters.dietFlags.formSymmetricDifference([diet])
                    }
                }
                FilterChip(title: RecipesCopy.quickFilter, isOn: model.filters.maxMinutes == 30) {
                    model.filters.maxMinutes = model.filters.maxMinutes == 30 ? nil : 30
                }
                ForEach(model.cuisines, id: \.self) { cuisine in
                    FilterChip(title: cuisine, isOn: model.filters.cuisine == cuisine) {
                        model.filters.cuisine = model.filters.cuisine == cuisine ? nil : cuisine
                    }
                }
            }
            .padding(.horizontal, LarderSpacing.l)
        }
    }
}

/// One toggle chip.
struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: LarderSpacing.xs) {
                if isOn {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .font(LarderFont.body(.subheadline, weight: .medium))
            .foregroundStyle(isOn ? LarderColor.ink.onAccent : LarderColor.ink.primary)
            .padding(.horizontal, LarderSpacing.m)
            .padding(.vertical, LarderSpacing.s)
            .frame(minHeight: 44)
            .background(isOn ? LarderColor.accent.second : LarderColor.surface.sunken, in: RoundedRectangle(cornerRadius: LarderRadius.field))
            .overlay {
                RoundedRectangle(cornerRadius: LarderRadius.field)
                    .strokeBorder(LarderColor.line.strong, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: LarderRadius.field))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#if DEBUG
#Preview("FilterChips") {
    FilterChips(model: PreviewData.model())
        .padding(.vertical, LarderSpacing.l)
        .background(LarderColor.surface.canvas)
}

#Preview("FilterChip selected") {
    HStack {
        FilterChip(title: "Vegan", isOn: true) {}
        FilterChip(title: "Dinner", isOn: false) {}
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
#endif
