import SwiftUI

/// One day in the week ledger: a stamped day name, its meals, a hairline below, and a brand tab when it is today.
public struct LedgerRow<Meals: View>: View {
    private let tabWidth: CGFloat = 3
    @ScaledSpacing(.m) private var gap
    private let day: String
    private let isToday: Bool
    private let meals: Meals

    /// Creates a row for a day.
    public init(day: String, isToday: Bool, @ViewBuilder meals: () -> Meals) {
        self.day = day
        self.isToday = isToday
        self.meals = meals()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(isToday ? LarderColor.accent.brand : Color.clear)
                .frame(width: tabWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: gap) {
                HStack(spacing: LarderSpacing.s) {
                    Text(day)
                        .stamp()
                        .foregroundStyle(LarderColor.ink.primary)
                    if isToday {
                        Text(Copy.Ledger.today)
                            .stamp()
                            .foregroundStyle(LarderColor.accent.brand)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                meals
            }
            .padding(.vertical, gap)
            .padding(.horizontal, LarderSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .contain)
    }
}

#Preview("LedgerRow") {
    VStack(spacing: 0) {
        LedgerRow(day: "Mon", isToday: false) {
            JarLabel(title: "Lentil soup", minutes: 35, tone: .ink, slot: "Dinner")
        }
        LedgerRow(day: "Tue", isToday: true) {
            JarLabel(title: "Chilli", minutes: 50, tone: .brand, slot: "Dinner")
            TapeLabel(text: "Chilli, day 2 of 4")
        }
        LedgerRow(day: "Wed", isToday: false) {
            JarLabel(title: "Spinach omelette", minutes: 15, tone: .second, slot: "Dinner")
        }
    }
    .background(LarderColor.surface.canvas)
}
