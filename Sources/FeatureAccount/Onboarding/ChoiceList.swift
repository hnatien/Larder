import LarderDesign
import SwiftUI

/// A list of tappable choices showing at most four at first; chosen ones beyond those stay visible.
struct ChoiceList<Choice: Hashable>: View {
    /// How a choice row draws its state.
    enum Mode {
        case multiple, single
    }

    static var visibleLimit: Int { 4 }

    let choices: [Choice]
    var mode: Mode = .multiple
    let title: (Choice) -> String
    let isSelected: (Choice) -> Bool
    let toggle: (Choice) -> Void
    @State private var showsAll = false

    private var visible: [Choice] {
        guard !showsAll else { return choices }
        return choices.enumerated()
            .filter { $0.offset < Self.visibleLimit || isSelected($0.element) }
            .map(\.element)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.xs) {
            ForEach(visible, id: \.self) { choice in
                ChoiceRow(title: title(choice), isSelected: isSelected(choice), mode: mode) {
                    toggle(choice)
                }
            }
            if choices.count > Self.visibleLimit {
                Button(showsAll ? AccountCopy.showFewer() : AccountCopy.showAll(choices.count)) {
                    showsAll.toggle()
                }
                .buttonStyle(.larderQuiet)
            }
        }
    }
}

/// One choice: a full-width button with a check or radio mark and the selected trait.
struct ChoiceRow<Choice: Hashable>: View {
    let title: String
    let isSelected: Bool
    let mode: ChoiceList<Choice>.Mode
    let action: () -> Void

    private var symbol: String {
        switch (mode, isSelected) {
        case (.multiple, true): "checkmark.square.fill"
        case (.multiple, false): "square"
        case (.single, true): "largecircle.fill.circle"
        case (.single, false): "circle"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: LarderSpacing.m) {
                Image(systemName: symbol)
                    .foregroundStyle(isSelected ? LarderColor.accent.brand : LarderColor.ink.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("ChoiceList") {
    @Previewable @State var chosen: Set<String> = ["Sesame"]
    let choices = ["Peanuts", "Tree nuts", "Milk", "Eggs", "Wheat", "Sesame"]
    ChoiceList(choices: choices, title: { $0 }, isSelected: { chosen.contains($0) }) { choice in
        if chosen.contains(choice) { chosen.remove(choice) } else { chosen.insert(choice) }
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
