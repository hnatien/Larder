import SwiftUI

/// One day in the week plan: a readable day heading with a Today badge, then that day's meals on a card.
public struct LedgerRow<Meals: View>: View {
    @ScaledSpacing(.s) private var gap
    private let day: String
    private let isToday: Bool
    private let meals: Meals

    /// Creates a row for a day; `day` is the visible heading, such as "Saturday 17 October".
    public init(day: String, isToday: Bool, @ViewBuilder meals: () -> Meals) {
        self.day = day
        self.isToday = isToday
        self.meals = meals()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            HStack(spacing: LarderSpacing.s) {
                Text(day)
                    .font(LarderFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(isToday ? LarderColor.accent.brand : LarderColor.ink.secondary)
                if isToday {
                    Pill(Copy.Ledger.today, tone: .brand)
                }
            }
            .padding(.horizontal, LarderSpacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            PaperCard {
                VStack(alignment: .leading, spacing: LarderSpacing.m) { meals }
            }
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: LarderRadius.panel, style: .continuous)
                        .strokeBorder(LarderColor.accent.brand, lineWidth: 1.5)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("LedgerRow") {
    VStack(spacing: LarderSpacing.l) {
        LedgerRow(day: "Monday 19 October", isToday: false) {
            JarLabel(title: "Lentil soup", minutes: 35, slot: "Dinner")
        }
        LedgerRow(day: "Tuesday 20 October", isToday: true) {
            JarLabel(title: "Chilli", minutes: 50, slot: "Dinner")
            TapeLabel(text: "Chilli, day 2 of 4")
        }
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
