import LarderDesign
import SwiftUI

/// Every choice as a wrapping set of capsule chips; nothing is hidden behind "Show all", so safety choices are always seen.
struct ChoiceList<Choice: Hashable>: View {
    let choices: [Choice]
    let title: (Choice) -> String
    let isSelected: (Choice) -> Bool
    let toggle: (Choice) -> Void

    var body: some View {
        ChipFlow {
            ForEach(choices, id: \.self) { choice in
                ChoiceChip(title(choice), isSelected: isSelected(choice)) { toggle(choice) }
            }
        }
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
