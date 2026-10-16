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
                        SectionHeading(LedgerCopy.nothingFits)
                        Text(LedgerView.spokenDay(date))
                            .stamp()
                            .foregroundStyle(LarderColor.ink.secondary)
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
        SectionHeading(entry.title)
        HStack(spacing: LarderSpacing.s) {
            Stamp(text: LedgerCopy.name(of: meal.slot))
            Stamp(text: Copy.Ledger.minutes(entry.minutes))
                .accessibilityLabel(Copy.Ledger.spokenMinutes(entry.minutes))
            ForEach(LedgerView.statusWords(meal), id: \.self) { word in
                Stamp(text: word)
            }
        }
        if let tag = entry.leftoverTag {
            TapeLabel(text: tag)
        }
        Button(LedgerCopy.seeRecipe) { onOpenRecipe(meal.recipeID) }
            .buttonStyle(.larderQuiet)

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

        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            Button(Copy.Action.swap) {
                Task { await loadSwaps(for: meal) }
            }
            .buttonStyle(.larderSecondary)
            if showsSwaps {
                swapList { option in
                    Task { await model.swap(meal, with: option) }
                    showsSwaps = false
                }
            }
            Button(Copy.Action.markCooked) { Task { await model.markCooked(meal) } }
                .buttonStyle(.larderSecondary)
                .disabled(meal.status == .cooked)
            Button(Copy.Action.skip) { Task { await model.skip(meal) } }
                .buttonStyle(.larderSecondary)
                .disabled(meal.status == .skipped)
            Button(meal.isLocked ? LedgerCopy.unlock : LedgerCopy.lock) {
                Task { meal.isLocked ? await model.unlock(meal) : await model.lock(meal) }
            }
            .buttonStyle(.larderSecondary)
            Picker(LedgerCopy.moveToAnotherDay, selection: moveBinding(for: meal)) {
                ForEach(model.days) { day in
                    Text(LedgerView.spokenDay(day.date)).tag(day.date)
                }
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)
            if meal.leftoverOf != nil {
                Button(LedgerCopy.removeLeftover) { Task { await model.removeLeftover(meal) } }
                    .buttonStyle(.larderQuiet)
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
                    VStack(alignment: .leading, spacing: LarderSpacing.s) {
                        Text(option.candidate.recipe.title)
                            .font(LarderFont.body(.body, weight: .semibold))
                            .foregroundStyle(LarderColor.ink.primary)
                        Stamp(text: Copy.Ledger.minutes(option.candidate.totalMinutes))
                            .accessibilityLabel(Copy.Ledger.spokenMinutes(option.candidate.totalMinutes))
                        if let reason = model.reasons(for: option, limit: 1).first {
                            ReasonLine(text: reason)
                        }
                        Button(LedgerCopy.useThis) { onChoose(option) }
                            .buttonStyle(.larderPrimary)
                            .accessibilityLabel(LedgerCopy.useRecipe(option.candidate.recipe.title))
                    }
                    .accessibilityElement(children: .contain)
                    Divider()
                        .overlay(LarderColor.line.hairline)
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
