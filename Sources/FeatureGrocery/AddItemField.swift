import LarderDesign
import SwiftUI

/// A text field and Add button for hand-written items.
struct AddItemField: View {
    let add: (String) -> Void
    @State private var text = ""

    private var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        AdaptiveStack(spacing: LarderSpacing.s) { field; addButton }
    }

    private var field: some View {
        TextField(GroceryCopy.itemToBuy, text: $text, prompt: Text(GroceryCopy.addAnItem))
            .font(LarderFont.body(.body))
            .textFieldStyle(.plain)
            .submitLabel(.done)
            .onSubmit(submit)
            .padding(LarderSpacing.m)
            .frame(minHeight: 44)
            .background(LarderColor.surface.sunken)
            .clipShape(RoundedRectangle(cornerRadius: LarderRadius.field))
    }

    private var addButton: some View {
        Button(GroceryCopy.add, action: submit)
            .buttonStyle(.larderSecondary)
            .disabled(isBlank)
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
