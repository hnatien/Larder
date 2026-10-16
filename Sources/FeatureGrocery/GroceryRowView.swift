import LarderDesign
import SwiftUI

/// One grocery line: a round check control, the name, the quantity stamp and a note when the pantry holds some.
struct GroceryRowView: View {
    let name: String
    let quantity: String
    let partiallyInPantry: Bool
    let isChecked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: LarderSpacing.m) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(LarderFont.body(.title3))
                    .foregroundStyle(isChecked ? LarderColor.accent.second : LarderColor.ink.tertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: LarderSpacing.xxs) {
                    Text(name)
                        .font(LarderFont.body(.body))
                        .foregroundStyle(isChecked ? LarderColor.ink.secondary : LarderColor.ink.primary)
                        .strikethrough(isChecked)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if partiallyInPantry {
                        MetaLabel(GroceryCopy.haveSome, systemImage: "refrigerator")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !quantity.isEmpty {
                    Text(quantity)
                        .font(LarderFont.body(.subheadline, weight: .medium))
                        .foregroundStyle(LarderColor.ink.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([GroceryCopy.markBought(name), quantity].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityValue(isChecked ? GroceryCopy.bought : GroceryCopy.toBuy)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("GroceryRowView") {
    VStack(spacing: LarderSpacing.s) {
        GroceryRowView(name: "Spinach", quantity: "200 g", partiallyInPantry: true, isChecked: false) {}
        GroceryRowView(name: "Rice", quantity: "500 g", partiallyInPantry: false, isChecked: true) {}
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.raised)
}
