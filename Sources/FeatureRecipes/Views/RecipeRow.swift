import LarderCore
import LarderDesign
import SwiftUI

/// A library row in the style of a jar label: title, a minutes stamp, then cuisine and diet words.
struct RecipeRow: View {
    let recipe: Recipe

    private var minutes: Int { recipe.prepMinutes + recipe.cookMinutes }

    private var words: [String] {
        let cuisine = recipe.tags.cuisine.map { [$0] } ?? []
        return cuisine + recipe.tags.dietFlags.map(RecipesCopy.name(of:)).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            Text(recipe.title)
                .font(LarderFont.body(.body, weight: .semibold))
                .foregroundStyle(LarderColor.ink.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            AdaptiveStack(spacing: LarderSpacing.s) { stamp; descriptor }
        }
        .padding(LarderSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LarderColor.surface.sunken, in: RoundedRectangle(cornerRadius: LarderRadius.stamp))
        .overlay {
            RoundedRectangle(cornerRadius: LarderRadius.stamp)
                .strokeBorder(LarderColor.line.strong, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([recipe.title, Copy.Ledger.spokenMinutes(minutes)] + words).joined(separator: ", "))
    }

    private var stamp: some View {
        Stamp(text: Copy.Ledger.minutes(minutes))
    }

    @ViewBuilder private var descriptor: some View {
        if !words.isEmpty {
            Text(words.joined(separator: " \u{B7} "))
                .font(LarderFont.body(.subheadline))
                .foregroundStyle(LarderColor.ink.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("RecipeRow") {
    VStack(spacing: LarderSpacing.m) {
        RecipeRow(recipe: PreviewData.chanaMasala)
        RecipeRow(recipe: PreviewData.porridge)
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
#endif
