import LarderCore
import LarderDesign
import SwiftUI

/// One pantry item: name, quantity stamp and freshness stamp, read as a single element with Eat it and Let it go actions.
struct ShelfRow: View {
    let item: PantryItem
    let level: FreshnessStyle.Level
    let onEat: () -> Void
    let onLetGo: () -> Void

    private var quantityText: String { ShelvesCopy.quantity(grams: item.quantityGrams) }

    private var spokenLabel: String {
        let word = FreshnessStyle(level).word
        let freshness = item.bestBy.map {
            Copy.Freshness.spoken(word: word, bestBy: $0.formatted(.dateTime.day().month(.wide)))
        } ?? word
        return ShelvesCopy.label(item: item.rawName, quantity: quantityText, freshness: freshness)
    }

    var body: some View {
        AdaptiveStack(spacing: LarderSpacing.m, stacksFrom: .xLarge) {
            name
                .frame(maxWidth: .infinity, alignment: .leading)
            quantity
            freshness
        }
        .padding(.vertical, LarderSpacing.xs)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityActions {
            actionButtons
        }
        .contextMenu {
            actionButtons
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: onEat) {
                Label(Copy.Action.eatIt, systemImage: "fork.knife")
            }
            .tint(LarderColor.accent.second)
            Button(action: onLetGo) {
                Label(Copy.Action.letItGo, systemImage: "leaf.arrow.circlepath")
            }
            .tint(LarderColor.ink.tertiary)
        }
    }

    private var name: some View {
        Text(item.rawName)
            .font(LarderFont.body(.body))
            .foregroundStyle(LarderColor.ink.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var quantity: some View {
        Stamp(text: quantityText)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var freshness: some View {
        FreshnessStamp(level: level, bestBy: item.bestBy)
    }

    @ViewBuilder private var actionButtons: some View {
        Button(Copy.Action.eatIt, action: onEat)
        Button(Copy.Action.letItGo, action: onLetGo)
    }
}

#if DEBUG
#Preview("ShelfRow") {
    List(PreviewData.items()) { item in
        ShelfRow(item: item, level: PreviewData.model().freshness(for: item), onEat: {}, onLetGo: {})
    }
    .listStyle(.plain)
}
#endif
