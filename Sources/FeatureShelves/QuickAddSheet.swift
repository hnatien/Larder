import LarderCore
import LarderDesign
import SwiftUI

/// Add food: type what you bought or tap common foods, check each line, then add them all from the toolbar.
struct QuickAddSheet: View {
    @Bindable var model: ShelvesModel
    @Environment(\.dismiss) private var dismiss
    @State private var isScanning = false

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
                #if os(iOS)
                Section {
                    Button(ShelvesCopy.scan, systemImage: "barcode.viewfinder") { isScanning = true }
                }
                .listRowBackground(LarderColor.surface.raised)
                #endif
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
        #if os(iOS)
        .fullScreenCover(isPresented: $isScanning) {
            PantryScannerSheet(model: model)
        }
        #endif
    }

    private var describeSection: some View {
        Section {
            heading(ShelvesCopy.draftLabel)
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
                    // Plain text, not a Label, so it wraps in a list row instead of clipping.
                    Image(systemName: "text.viewfinder")
                        .accessibilityHidden(true)
                    Text(ShelvesCopy.parse)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.larderSecondary)
            .disabled(model.isParsing || isDraftBlank)
            Text(ShelvesCopy.draftHint)
                .font(LarderFont.body(.footnote))
                .foregroundStyle(LarderColor.ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(LarderColor.surface.raised)
    }

    /// A section's heading as its first row; Form section headers and footers do not fully scale with Dynamic Type.
    private func heading(_ title: String) -> some View {
        Text(title)
            .font(LarderFont.body(.headline, weight: .semibold))
            .foregroundStyle(LarderColor.ink.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var staplesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: LarderSpacing.s) {
                heading(ShelvesCopy.staplesTitle)
                ChipFlow {
                    ForEach(ShelvesCopy.staples) { staple in
                        ChoiceChip(staple.name, systemImage: "plus", isSelected: model.isPending(staple)) {
                            model.toggle(staple)
                        }
                    }
                }
                // The lines a chip adds land further down, so the count says where they went; in the chips' own
                // row, since section footers do not fully scale with Dynamic Type.
                if !model.pendingLines.isEmpty {
                    Text(ShelvesCopy.checkBelow(model.pendingLines.count))
                        .font(LarderFont.body(.footnote, weight: .semibold))
                        .foregroundStyle(LarderColor.ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, LarderSpacing.xs)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private var linesSection: some View {
        Section {
            heading(ShelvesCopy.checkTitle)
            ForEach(model.pendingLines) { line in
                DraftLineEditor(line: binding(for: line), defaultBestBy: model.now) {
                    model.pendingLines.removeAll { $0.id == line.id }
                }
            }
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
