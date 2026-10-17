import LarderDesign
import SwiftUI

/// A text field for hand-written items, with an Add button that appears once there is something to add.
struct AddItemField: View {
    let add: (String) -> Void
    @State private var text = ""

    private var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: LarderSpacing.s) {
            Image(systemName: "plus.circle.fill")
                .font(LarderFont.body(.title3))
                .foregroundStyle(LarderColor.accent.brand)
                .accessibilityHidden(true)
            // Vertical so it grows with Dynamic Type instead of clipping; Return adds the item rather than a new line.
            TextField(GroceryCopy.itemToBuy, text: $text, prompt: Text(GroceryCopy.addAnItem).foregroundStyle(LarderColor.ink.tertiary), axis: .vertical)
                .font(LarderFont.body(.body))
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .onSubmit(submit)
                .onChange(of: text) { _, new in
                    if new.contains("\n") {
                        text = new.replacingOccurrences(of: "\n", with: "")
                        submit()
                    }
                }
                .frame(minHeight: 44)
            if !isBlank {
                Button(GroceryCopy.add, action: submit)
                    .buttonStyle(.larderSecondary)
                    .transition(.opacity)
            }
        }
        .larderAnimation(LarderMotion.tap, value: isBlank)
    }

    private func submit() {
        guard !isBlank else { return }
        add(text)
        text = ""
    }
}

#Preview("AddItemField") {
    AddItemField { _ in }
        .padding(LarderSpacing.l)
        .background(LarderColor.surface.canvas)
}
