import LarderCore
import LarderDesign
import SwiftUI

/// A library ledger row on the canvas: title, a minutes stamp, then cuisine and diet words. The list draws the hairline
/// between rows; the row has no card or border of its own.
struct RecipeRow: View {
    @ScaledSpacing(.m) private var gap
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
        .padding(.vertical, gap)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
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
    VStack(spacing: 0) {
        RecipeRow(recipe: PreviewData.chanaMasala)
        Divider().overlay(LarderColor.line.hairline)
        RecipeRow(recipe: PreviewData.porridge)
        Divider().overlay(LarderColor.line.hairline)
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
#endif
