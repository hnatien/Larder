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
        HStack(alignment: .top, spacing: LarderSpacing.m) {
            Button(action: toggle) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isChecked ? LarderColor.accent.second : LarderColor.ink.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(GroceryCopy.markBought(name))
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isChecked ? GroceryCopy.bought : GroceryCopy.toBuy)

            VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                Text(name)
                    .font(LarderFont.body(.body))
                    .foregroundStyle(isChecked ? LarderColor.ink.secondary : LarderColor.ink.primary)
                    .strikethrough(isChecked)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if partiallyInPantry {
                    ReasonLine(text: GroceryCopy.haveSome)
                }
            }
            .padding(.top, LarderSpacing.m)
            Spacer(minLength: LarderSpacing.s)
            if !quantity.isEmpty {
                Stamp(text: quantity)
                    .padding(.top, LarderSpacing.m)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("GroceryRowView") {
    VStack(spacing: LarderSpacing.s) {
        GroceryRowView(name: "Spinach", quantity: "200 g", partiallyInPantry: true, isChecked: false) {}
        GroceryRowView(name: "Rice", quantity: "500 g", partiallyInPantry: false, isChecked: true) {}
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
