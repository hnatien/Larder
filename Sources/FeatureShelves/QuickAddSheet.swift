import LarderCore
import LarderDesign
import SwiftUI

/// Add food: type what you bought or tap common foods, check each line, then add them all from the toolbar.
struct QuickAddSheet: View {
    @Bindable var model: ShelvesModel
    @Environment(\.dismiss) private var dismiss

    private var isDraftBlank: Bool {
        model.quickAddDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error = model.error {
                    Section {
                        ErrorBanner(error: error, onDismiss: model.clearError)
                    }
                    .listRowBackground(LarderColor.surface.raised)
                }
                describeSection
                staplesSection
                if !model.pendingLines.isEmpty {
                    linesSection
                }
                Section {
                    Button(ShelvesCopy.addByHand, systemImage: "plus.circle", action: model.addBlankLine)
                }
                .listRowBackground(LarderColor.surface.raised)
            }
            .larderList()
            .navigationTitle(ShelvesCopy.sheetTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ShelvesCopy.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ShelvesCopy.addItems(model.confirmableLines.count)) { confirm() }
                        .disabled(model.confirmableLines.isEmpty)
                }
            }
        }
        .onChange(of: model.error) { _, error in
            if let error {
                AccessibilityNotification.Announcement(ShelvesCopy.message(for: error)).post()
            }
        }
        .onDisappear { model.discardPending() }
    }

    private var describeSection: some View {
        Section {
            TextField(ShelvesCopy.draftLabel, text: $model.quickAddDraft, prompt: Text(ShelvesCopy.draftPrompt), axis: .vertical)
                .lineLimit(2...6)
                .submitLabel(.done)
                .onSubmit { Task { await model.quickAdd() } }
            Button {
                Task { await model.quickAdd() }
            } label: {
                HStack(spacing: LarderSpacing.s) {
                    if model.isParsing {
                        ProgressView()
                    }
                    Label(ShelvesCopy.parse, systemImage: "text.viewfinder")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.larderSecondary)
            .disabled(model.isParsing || isDraftBlank)
        } header: {
            Text(ShelvesCopy.draftLabel)
                .font(LarderFont.body(.headline, weight: .semibold))
                .foregroundStyle(LarderColor.ink.primary)
                .textCase(nil)
        } footer: {
            Text(ShelvesCopy.draftHint)
                .font(LarderFont.body(.footnote))
                .foregroundStyle(LarderColor.ink.secondary)
        }
        .listRowBackground(LarderColor.surface.raised)
    }

    private var staplesSection: some View {
        Section {
            ChipFlow {
                ForEach(ShelvesCopy.staples) { staple in
                    ChoiceChip(staple.name, systemImage: "plus", isSelected: model.isPending(staple)) {
                        model.toggle(staple)
                    }
                }
            }
            .padding(.vertical, LarderSpacing.xs)
        } header: {
            Text(ShelvesCopy.staplesTitle)
                .font(LarderFont.body(.headline, weight: .semibold))
                .foregroundStyle(LarderColor.ink.primary)
                .textCase(nil)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private var linesSection: some View {
        Section {
            ForEach(model.pendingLines) { line in
                DraftLineEditor(line: binding(for: line), defaultBestBy: model.now) {
                    model.pendingLines.removeAll { $0.id == line.id }
                }
            }
        } header: {
            Text(ShelvesCopy.checkTitle)
                .font(LarderFont.body(.headline, weight: .semibold))
                .foregroundStyle(LarderColor.ink.primary)
                .textCase(nil)
        }
        .listRowBackground(LarderColor.surface.raised)
    }

    /// A binding that finds the line by its ID, so removing a line (Cancel, a staple chip, the minus button) never
    /// leaves a row reading past the end of the array while it disappears.
    private func binding(for line: DraftLine) -> Binding<DraftLine> {
        Binding(
            get: { model.pendingLines.first { $0.id == line.id } ?? line },
            set: { edited in
                guard let index = model.pendingLines.firstIndex(where: { $0.id == line.id }) else { return }
                model.pendingLines[index] = edited
            }
        )
    }

    private func confirm() {
        Task {
            let added = await model.confirmPending()
            if added > 0 {
                AccessibilityNotification.Announcement(ShelvesCopy.added(added)).post()
            }
            if model.pendingLines.isEmpty { dismiss() }
        }
    }
}

#if DEBUG
#Preview("QuickAddSheet") {
    QuickAddSheet(
        model: PreviewData.model(
            pendingLines: [
                DraftLine(name: "Rice", quantity: 2, unit: .cup, source: .naturalLanguage),
                DraftLine(name: "Spinach", quantity: 200, unit: .gram, location: .fridge, source: .naturalLanguage),
            ]
        )
    )
}

#Preview("QuickAddSheet empty") {
    QuickAddSheet(model: PreviewData.model())
}
#endif
