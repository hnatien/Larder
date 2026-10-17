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
        var parts = [quantity]
        if showsLocation { parts.append(ShelvesCopy.name(of: item.location)) }
        // A fresh item has no stamp, so its date, when it has one, goes here.
        if level == .fresh, let bestBy = item.bestBy {
            parts.append(ShelvesCopy.bestBy(FreshnessStamp.dateText(bestBy, now: .now)))
        }
        return parts.joined(separator: " \u{B7} ")
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

/// Edits one item's name, amount, place and best-by date; Used up and Throw away remove it. An item counted in pieces,
/// such as eggs, is edited as a count with a stepper, so using some is one tap.
struct ShelfItemEditor: View {
    let model: ShelvesModel
    @State private var draft: PantryItem
    @State private var hasBestBy: Bool
    /// The portion the item is counted in when it opened; `nil` edits grams.
    private let countedIn: Portion?
    /// The grams as typed, so a half-typed number such as "12." is kept while editing.
    @State private var amountText: String
    @Environment(\.dismiss) private var dismiss

    init(model: ShelvesModel, item: PantryItem) {
        self.model = model
        _draft = State(initialValue: item)
        _hasBestBy = State(initialValue: item.bestBy != nil)
        countedIn = model.count(for: item)?.portion
        _amountText = State(initialValue: item.quantityGrams.formatted(.number.precision(.fractionLength(0...1)).grouping(.never)))
    }

    /// The amount: a count with a stepper for an item counted in pieces, else grams to type.
    @ViewBuilder private var amount: some View {
        if let portion = countedIn {
            Stepper(value: count(in: portion), in: 1...ShelvesModel.maximumCount) {
                Text(ShelvesCopy.count(count(in: portion).wrappedValue, of: portion))
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityLabel(ShelvesCopy.amount)
            .accessibilityValue(ShelvesCopy.count(count(in: portion).wrappedValue, of: portion))
        } else {
            // A label above a growing field, so neither clips at the largest text sizes.
            VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                Text(ShelvesCopy.amountGrams)
                    .font(LarderFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                field(ShelvesCopy.amountGrams, text: $amountText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .onChange(of: amountText) { _, text in
                        // An amount that is not a number counts as none, so Save stays off until it is one.
                        draft.quantityGrams = Self.grams(from: text) ?? 0
                    }
                Text(model.quantityText(for: draft))
                    .font(LarderFont.body(.subheadline))
                    .foregroundStyle(LarderColor.ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A text field on a sunken well that grows with Dynamic Type.
    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text, prompt: Text(title).foregroundStyle(LarderColor.ink.tertiary), axis: .vertical)
            .foregroundStyle(LarderColor.ink.primary)
            .padding(LarderSpacing.m)
            .frame(minHeight: 44)
            .background(LarderColor.surface.sunken, in: RoundedRectangle(cornerRadius: LarderRadius.field))
    }

    /// Moves the best-by date a number of days, starting from today when there is none.
    private func shiftBestBy(by days: Int) {
        let start = draft.bestBy ?? model.now
        draft.bestBy = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
    }

    /// Grams from typed text in the current locale's number format, or `nil` when it is not a number.
    static func grams(from text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try? Double(trimmed, format: .number.locale(locale))
    }

    private func count(in portion: Portion) -> Binding<Int> {
        Binding(
            get: { max(Int((draft.quantityGrams / portion.grams).rounded()), 1) },
            set: { draft.quantityGrams = Double($0) * portion.grams }
        )
    }

    private var isValid: Bool {
        !draft.rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.quantityGrams > 0
    }

    var body: some View {
        NavigationStack {
            // Plain stacks on paper cards rather than a Form, whose rows do not fully scale with Dynamic Type.
            ScrollView {
                VStack(alignment: .leading, spacing: LarderSpacing.l) {
                    PaperCard {
                        VStack(alignment: .leading, spacing: LarderSpacing.m) {
                            field(ShelvesCopy.name, text: $draft.rawName)
                                .font(LarderFont.body(.body, weight: .semibold))
                            Divider().overlay(LarderColor.line.hairline)
                            amount
                        }
                    }
                    PaperCard {
                        VStack(alignment: .leading, spacing: LarderSpacing.m) {
                            AdaptiveStack(spacing: LarderSpacing.m, stacksFrom: .xLarge) {
                                Text(ShelvesCopy.location)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Picker(ShelvesCopy.location, selection: $draft.location) {
                                    ForEach(StorageLocation.allCases, id: \.self) { Text(ShelvesCopy.name(of: $0)).tag($0) }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .tint(LarderColor.accent.brand)
                            }
                            .frame(minHeight: 44)
                            Divider().overlay(LarderColor.line.hairline)
                            Toggle(isOn: $hasBestBy) {
                                Text(ShelvesCopy.hasBestBy)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .tint(LarderColor.accent.second)
                            .frame(minHeight: 44)
                            if hasBestBy {
                                // A day stepper with the date in words, rather than Apple's date picker, whose labels
                                // do not scale with Dynamic Type; holding a button steps quickly.
                                Stepper {
                                    Text(ShelvesCopy.bestBy((draft.bestBy ?? model.now).formatted(.dateTime.weekday(.wide).day().month(.wide))))
                                        .fixedSize(horizontal: false, vertical: true)
                                } onIncrement: {
                                    shiftBestBy(by: 1)
                                } onDecrement: {
                                    shiftBestBy(by: -1)
                                }
                                .frame(minHeight: 44)
                            }
                        }
                        .font(LarderFont.body(.body))
                        .foregroundStyle(LarderColor.ink.primary)
                    }
                    AdaptiveStack(spacing: LarderSpacing.s, stacksFrom: .xLarge) {
                        Button {
                            Task {
                                await model.eat(draft)
                                dismiss()
                            }
                        } label: {
                            Text(Copy.Action.eatIt).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.larderSecondary)
                        Button(role: .destructive) {
                            Task {
                                await model.letGo(draft)
                                dismiss()
                            }
                        } label: {
                            Text(Copy.Action.letItGo).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.larderQuiet)
                    }
                }
                .padding(LarderSpacing.l)
            }
            .background(LarderColor.surface.canvas)
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
