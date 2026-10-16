import LarderCore
import LarderDesign
import SwiftUI

/// One pantry item: name, amount and, when it needs using, a freshness badge. Tapping opens the editor; Used up and
/// Throw away are swipe, context-menu and VoiceOver actions.
struct ShelfRow: View {
    let item: PantryItem
    let quantity: String
    let level: FreshnessStyle.Level
    /// Shown under the name on the Use soon list, where items from every location sit together.
    var showsLocation = false
    let onEdit: () -> Void
    let onEat: () -> Void
    let onLetGo: () -> Void

    private var subtitle: String {
        showsLocation ? [quantity, ShelvesCopy.name(of: item.location)].joined(separator: " \u{B7} ") : quantity
    }

    private var spokenLabel: String {
        let word = FreshnessStyle(level).word
        let freshness = item.bestBy.map {
            Copy.Freshness.spoken(word: word, bestBy: $0.formatted(.dateTime.day().month(.wide)))
        } ?? word
        return ShelvesCopy.label(item: item.rawName, quantity: subtitle, freshness: freshness)
    }

    var body: some View {
        Button(action: onEdit) {
            AdaptiveStack(spacing: LarderSpacing.m, stacksFrom: .xLarge) {
                VStack(alignment: .leading, spacing: LarderSpacing.xxs) {
                    Text(item.rawName)
                        .font(LarderFont.body(.body, weight: .medium))
                        .foregroundStyle(LarderColor.ink.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(LarderFont.body(.subheadline))
                        .foregroundStyle(LarderColor.ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if level != .fresh {
                    FreshnessStamp(level: level, bestBy: item.bestBy)
                }
            }
            .padding(.vertical, LarderSpacing.xs)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(ShelvesCopy.editTitle)
        .accessibilityActions {
            actionButtons
        }
        .contextMenu {
            Button(ShelvesCopy.editTitle, systemImage: "pencil", action: onEdit)
            actionButtons
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: onEat) {
                Label(Copy.Action.eatIt, systemImage: "checkmark")
            }
            .tint(LarderColor.accent.second)
            Button(action: onLetGo) {
                Label(Copy.Action.letItGo, systemImage: "trash")
            }
            .tint(LarderColor.ink.tertiary)
        }
    }

    @ViewBuilder private var actionButtons: some View {
        Button(Copy.Action.eatIt, systemImage: "checkmark", action: onEat)
        Button(Copy.Action.letItGo, systemImage: "trash", action: onLetGo)
    }
}

/// Edits one item's name, amount, place and best-by date; Used up and Throw away remove it.
struct ShelfItemEditor: View {
    let model: ShelvesModel
    @State private var draft: PantryItem
    @State private var hasBestBy: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: ShelvesModel, item: PantryItem) {
        self.model = model
        _draft = State(initialValue: item)
        _hasBestBy = State(initialValue: item.bestBy != nil)
    }

    private var isValid: Bool {
        !draft.rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.quantityGrams > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(ShelvesCopy.name, text: $draft.rawName)
                        .font(LarderFont.body(.body, weight: .semibold))
                    LabeledContent(ShelvesCopy.amountGrams) {
                        TextField(ShelvesCopy.amountGrams, value: $draft.quantityGrams, format: .number.precision(.fractionLength(0...1)))
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    Text(model.quantityText(for: draft))
                        .font(LarderFont.body(.subheadline))
                        .foregroundStyle(LarderColor.ink.secondary)
                }
                Section {
                    Picker(ShelvesCopy.location, selection: $draft.location) {
                        ForEach(StorageLocation.allCases, id: \.self) { Text(ShelvesCopy.name(of: $0)).tag($0) }
                    }
                    Toggle(ShelvesCopy.hasBestBy, isOn: $hasBestBy)
                        .tint(LarderColor.accent.second)
                    if hasBestBy {
                        DatePicker(
                            ShelvesCopy.bestBy,
                            selection: Binding(get: { draft.bestBy ?? model.now }, set: { draft.bestBy = $0 }),
                            displayedComponents: .date
                        )
                    }
                }
                Section {
                    Button(Copy.Action.eatIt, systemImage: "checkmark") {
                        Task {
                            await model.eat(draft)
                            dismiss()
                        }
                    }
                    Button(Copy.Action.letItGo, systemImage: "trash", role: .destructive) {
                        Task {
                            await model.letGo(draft)
                            dismiss()
                        }
                    }
                }
            }
            .larderList()
            .navigationTitle(ShelvesCopy.editTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ShelvesCopy.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ShelvesCopy.save) {
                        var saved = draft
                        if !hasBestBy { saved.bestBy = nil }
                        Task {
                            await model.update(saved)
                            dismiss()
                        }
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

#if DEBUG
#Preview("ShelfRow") {
    let model = PreviewData.model()
    List(PreviewData.items()) { item in
        ShelfRow(item: item, quantity: model.quantityText(for: item), level: model.freshness(for: item), onEdit: {}, onEat: {}, onLetGo: {})
    }
    .listStyle(.plain)
}
#endif
