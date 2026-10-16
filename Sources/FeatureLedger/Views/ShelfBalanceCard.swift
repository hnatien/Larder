import LarderCore
import LarderDesign
import SwiftUI

/// The week's nutrition balance: one band per food group and a sentence about the gap. Numbers only when the profile asks for them.
struct ShelfBalanceCard: View {
    let balance: ShelfBalance
    let sentence: String?
    /// Per-day averages to list; empty unless the profile shows numbers.
    let averages: [NutrientNote]

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: LarderSpacing.m) {
                VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                    SectionHeading(LedgerCopy.shelfHeading)
                    Text(LedgerCopy.balanceLegend)
                        .font(LarderFont.body(.footnote))
                        .foregroundStyle(LarderColor.ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(FoodGroup.allCases.filter { balance.levels[$0] != nil }, id: \.self) { group in
                    ShelfBand(group: group, level: Self.level(balance.levels[group] ?? .comfortable))
                }
                if let sentence {
                    ReasonLine(text: sentence)
                }
                if !averages.isEmpty {
                    VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                        Text(LedgerCopy.perDayHeading)
                            .font(LarderFont.body(.subheadline, weight: .semibold))
                            .foregroundStyle(LarderColor.ink.primary)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(averages, id: \.nutrient) { note in
                            if let line = LedgerCopy.average(note) {
                                Text(line)
                                    .font(LarderFont.body(.body))
                                    .foregroundStyle(LarderColor.ink.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    static func level(_ level: BalanceLevel) -> ShelfBand.Level {
        switch level {
        case .light: .light
        case .comfortable: .comfortable
        case .heavy: .heavy
        }
    }
}

#if DEBUG
#Preview("ShelfBalanceCard") {
    let balance = ShelfBalance(levels: [
        .produce: .light, .grains: .comfortable, .protein: .comfortable, .dairy: .heavy, .fats: .comfortable, .legumes: .comfortable,
    ])
    ScrollView {
        VStack(spacing: LarderSpacing.l) {
            ShelfBalanceCard(balance: balance, sentence: LedgerCopy.balanceSentence(for: balance), averages: [])
            ShelfBalanceCard(
                balance: balance,
                sentence: nil,
                averages: [
                    NutrientNote(nutrient: .energy, totalPerDay: 2040, min: 1800, max: 2200, status: .within),
                    NutrientNote(nutrient: .fiber, totalPerDay: 24, min: 28, max: nil, status: .under),
                ]
            )
        }
        .padding(LarderSpacing.l)
    }
    .background(LarderColor.surface.canvas)
}
#endif
