import LarderCore
import LarderDesign
import SwiftUI

/// One meal up close: its reasons and every change the ledger offers, each a plain tap.
struct MealSheet: View {
    let model: LedgerModel
    let target: LedgerSheet
    let onOpenRecipe: (RecipeID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsSwaps = false
    @State private var isLoadingSwaps = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LarderSpacing.l) {
                    if let error = model.error {
                        LedgerNotice(error: error, onDismiss: model.clearError)
                    }
                    switch target {
                    case .meal(let id, _):
                        if let entry = entry(id) {
                            mealContent(entry)
                        }
                    case .openSlot(let date, let slot):
                        SectionHeading(LedgerCopy.pickOne)
                        MetaLabel(LedgerView.spokenDay(date), systemImage: "calendar")
                        swapList { option in
                            Task {
                                await model.fill(slot, on: date, with: option)
                                if model.error == nil { dismiss() }
                            }
                        }
                    }
                }
                .padding(LarderSpacing.l)
            }
            .background(LarderColor.surface.canvas)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LedgerCopy.done) { dismiss() }
                }
            }
        }
        .task { await openSwapsIfAsked() }
        .onChange(of: model.meals) {
            if case .meal(let id, _) = target, entry(id) == nil { dismiss() }
        }
    }

    private func entry(_ id: PlannedMealID) -> LedgerMeal? {
        model.days.lazy.flatMap(\.meals).first { $0.id == id }
    }

    @ViewBuilder private func mealContent(_ entry: LedgerMeal) -> some View {
        let meal = entry.meal
        HStack(alignment: .top, spacing: LarderSpacing.m) {
            RecipeImage(title: entry.title, photoFileName: entry.photoFileName, size: .large)
            VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                Text(entry.title)
                    .font(LarderFont.display(.title2))
                    .foregroundStyle(LarderColor.ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                MetaLabel(
                    [LedgerCopy.name(of: meal.slot), Copy.Ledger.minutes(entry.minutes)].joined(separator: " \u{B7} "),
                    systemImage: "clock",
                    spoken: [LedgerCopy.name(of: meal.slot), Copy.Ledger.spokenMinutes(entry.minutes)].joined(separator: ", ")
                )
                MetaLabel(LedgerView.spokenDay(meal.date), systemImage: "calendar")
                if !LedgerView.statusWords(meal).isEmpty {
                    HStack(spacing: LarderSpacing.xs) {
                        ForEach(LedgerView.statusWords(meal), id: \.self) { Pill($0) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let tag = entry.leftoverTag {
            TapeLabel(text: tag)
        }
        AdaptiveStack(spacing: LarderSpacing.s, stacksFrom: .xLarge) {
            Button {
                onOpenRecipe(meal.recipeID)
            } label: {
                Label(LedgerCopy.seeRecipe, systemImage: "book").frame(maxWidth: .infinity)
            }
            .buttonStyle(.larderPrimary)
            Button {
                Task { await loadSwaps(for: meal) }
            } label: {
                Label(Copy.Action.swap, systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity)
            }
            .buttonStyle(.larderSecondary)
        }
        if showsSwaps {
            swapList { option in
                Task { await model.swap(meal, with: option) }
                showsSwaps = false
            }
        }

        let reasons = model.reasons(for: meal)
        let note = model.explanationNote(for: meal)
        if !reasons.isEmpty || note != nil {
            VStack(alignment: .leading, spacing: LarderSpacing.s) {
                Text(LedgerCopy.whyThis)
                    .font(LarderFont.body(.headline, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.primary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(reasons, id: \.self) { ReasonLine(text: $0) }
                if let note {
                    ReasonLine(text: note)
                }
            }
        }

        PaperCard(padded: false) {
            VStack(alignment: .leading, spacing: 0) {
                ActionRow(title: Copy.Action.markCooked, systemImage: "checkmark.circle") {
                    Task { await model.markCooked(meal) }
                }
                .disabled(meal.status == .cooked)
                Divider().overlay(LarderColor.line.hairline).padding(.leading, LarderSpacing.l)
                if meal.status == .skipped {
                    ActionRow(title: LedgerCopy.markPlanned, systemImage: "arrow.uturn.backward") {
                        Task { await model.markPlanned(meal) }
                    }
                } else {
                    ActionRow(title: Copy.Action.skip, systemImage: "forward") {
                        Task { await model.skip(meal) }
                    }
                    .disabled(meal.status == .cooked)
                }
                Divider().overlay(LarderColor.line.hairline).padding(.leading, LarderSpacing.l)
                ActionRow(title: meal.isLocked ? LedgerCopy.unlock : LedgerCopy.lock, systemImage: meal.isLocked ? "lock.open" : "lock") {
                    Task { meal.isLocked ? await model.unlock(meal) : await model.lock(meal) }
                }
                Divider().overlay(LarderColor.line.hairline).padding(.leading, LarderSpacing.l)
                Picker(selection: moveBinding(for: meal)) {
                    ForEach(model.days) { day in
                        Text(LedgerView.spokenDay(day.date)).tag(day.date)
                    }
                } label: {
                    Label(LedgerCopy.moveToAnotherDay, systemImage: "calendar")
                }
                .pickerStyle(.menu)
                .tint(LarderColor.accent.brand)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, LarderSpacing.l)
                .padding(.vertical, LarderSpacing.xs)
                if meal.leftoverOf != nil {
                    Divider().overlay(LarderColor.line.hairline).padding(.leading, LarderSpacing.l)
                    ActionRow(title: LedgerCopy.removeLeftover, systemImage: "minus.circle") {
                        Task { await model.removeLeftover(meal) }
                    }
                }
            }
        }
    }

    private func moveBinding(for meal: PlannedMeal) -> Binding<Date> {
        Binding(
            get: { meal.date },
            set: { date in Task { await model.moveMeal(meal, to: date) } }
        )
    }

    @ViewBuilder private func swapList(onChoose: @escaping (ScoredRecipe) -> Void) -> some View {
        if isLoadingSwaps {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if model.swapCandidates.isEmpty {
            Text(LedgerCopy.noSwaps)
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.secondary)
        } else {
            VStack(alignment: .leading, spacing: LarderSpacing.m) {
                ForEach(model.swapCandidates, id: \.recipeID) { option in
                    PaperCard {
                        VStack(alignment: .leading, spacing: LarderSpacing.s) {
                            HStack(spacing: LarderSpacing.m) {
                                RecipeImage(title: option.candidate.recipe.title, photoFileName: option.candidate.recipe.photoFileName, size: .small)
                                VStack(alignment: .leading, spacing: LarderSpacing.xxs) {
                                    Text(option.candidate.recipe.title)
                                        .font(LarderFont.body(.body, weight: .semibold))
                                        .foregroundStyle(LarderColor.ink.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    MetaLabel(
                                        Copy.Ledger.minutes(option.candidate.totalMinutes),
                                        systemImage: "clock",
                                        spoken: Copy.Ledger.spokenMinutes(option.candidate.totalMinutes)
                                    )
                                }
                            }
                            if let reason = model.reasons(for: option, limit: 1).first {
                                ReasonLine(text: reason)
                            }
                            Button(LedgerCopy.useThis) { onChoose(option) }
                                .buttonStyle(.larderPrimary)
                                .accessibilityLabel(LedgerCopy.useRecipe(option.candidate.recipe.title))
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }

    private func openSwapsIfAsked() async {
        switch target {
        case .meal(let id, let swapping):
            if swapping, let meal = entry(id)?.meal { await loadSwaps(for: meal) }
        case .openSlot(let date, let slot):
            isLoadingSwaps = true
            await model.loadCandidates(forOpenSlot: slot, on: date)
            isLoadingSwaps = false
        }
    }

    private func loadSwaps(for meal: PlannedMeal) async {
        showsSwaps = true
        isLoadingSwaps = true
        await model.loadSwapCandidates(for: meal)
        isLoadingSwaps = false
    }
}

/// One row in the meal sheet's action list: an icon and a verb, the whole row tappable.
private struct ActionRow: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(LarderFont.body(.body))
                .foregroundStyle(isEnabled ? LarderColor.ink.primary : LarderColor.ink.tertiary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, LarderSpacing.l)
                .padding(.vertical, LarderSpacing.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
private struct MealSheetPreview: View {
    let model = PreviewKitchen.ledgerModel()
    let swapping: Bool

    var body: some View {
        Group {
            if let meal = model.meals.first(where: { $0.leftoverOf == nil }) {
                MealSheet(model: model, target: .meal(meal.id, swapping: swapping), onOpenRecipe: { _ in })
            } else {
                ProgressView()
            }
        }
        .task { await model.load() }
        .larderTheme()
    }
}

#Preview("MealSheet") {
    MealSheetPreview(swapping: false)
}

#Preview("MealSheet swapping") {
    MealSheetPreview(swapping: true)
}
#endif
