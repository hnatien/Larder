import LarderCore
import LarderDesign
import SwiftUI

/// A library row: the photo or dish tile, the title, the time, cuisine and diet words, and a chevron.
struct RecipeRow: View {
    @ScaledSpacing(.m) private var gap
    let recipe: Recipe
    var isFavourite = false
    /// How much of it is on the shelves; shown when Larder can match at least two of its foods.
    var coverage: PantryCoverage?

    private var coverageText: String? {
        coverage.flatMap { $0.total >= 2 ? RecipesCopy.youHave($0) : nil }
    }

    private var minutes: Int { recipe.prepMinutes + recipe.cookMinutes }

    /// Cuisine, then diets; vegetarian is dropped when vegan says it already.
    private var words: [String] {
        let cuisine = recipe.tags.cuisine.map { [$0] } ?? []
        var diets = recipe.tags.dietFlags
        if diets.contains(.vegan) { diets.remove(.vegetarian) }
        return cuisine + diets.map(RecipesCopy.name(of:)).sorted()
    }

    var body: some View {
        HStack(spacing: LarderSpacing.m) {
            RecipeImage(title: recipe.title, photoFileName: recipe.photoFileName, size: .medium)
            VStack(alignment: .leading, spacing: LarderSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: LarderSpacing.xs) {
                    Text(recipe.title)
                        .font(LarderFont.body(.body, weight: .semibold))
                        .foregroundStyle(LarderColor.ink.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if isFavourite {
                        Image(systemName: "heart.fill")
                            .font(LarderFont.body(.footnote))
                            .foregroundStyle(LarderColor.accent.brand)
                    }
                }
                AdaptiveStack(spacing: LarderSpacing.m, stacksFrom: .accessibility1) {
                    MetaLabel(Copy.Ledger.minutes(minutes), systemImage: "clock", spoken: Copy.Ledger.spokenMinutes(minutes))
                    if let coverageText {
                        MetaLabel(coverageText, systemImage: "refrigerator")
                    }
                }
                if !words.isEmpty {
                    Text(words.joined(separator: " \u{B7} "))
                        .font(LarderFont.body(.footnote))
                        .foregroundStyle(LarderColor.ink.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(LarderFont.body(.footnote, weight: .semibold))
                .foregroundStyle(LarderColor.ink.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, LarderSpacing.l)
        .padding(.vertical, gap)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ([recipe.title] + (isFavourite ? [RecipesCopy.favourites] : []) + [Copy.Ledger.spokenMinutes(minutes)]
                + [coverageText].compactMap { $0 } + words).joined(separator: ", ")
        )
    }
}

#if DEBUG
#Preview("RecipeRow") {
    VStack(spacing: 0) {
        RecipeRow(recipe: PreviewData.chanaMasala, isFavourite: true, coverage: PantryCoverage(have: 3, total: 5))
        Divider().overlay(LarderColor.line.hairline)
        RecipeRow(recipe: PreviewData.porridge)
    }
    .background(LarderColor.surface.raised)
}
#endif
