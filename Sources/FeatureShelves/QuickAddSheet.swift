import LarderCore
import LarderDesign
import SwiftUI

/// Describe what you bought, check the parsed lines, then add them; the same sheet takes lines typed by hand.
struct QuickAddSheet: View {
    @Bindable var model: ShelvesModel
    @Environment(\.dismiss) private var dismiss

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
                if !model.pendingLines.isEmpty {
                    linesSection
                }
                confirmSection
            }
            .larderList()
            .navigationTitle(ShelvesCopy.sheetTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .onChange(of: model.error) { _, error in
            if let error {
                AccessibilityNotification.Announcement(ShelvesCopy.message(for: error)).post()
            }
        }
    }

    private var describeSection: some View {
        Section {
            TextField(ShelvesCopy.draftPrompt, text: $model.quickAddDraft, axis: .vertical)
                .lineLimit(3...8)
            Button {
                Task { await model.quickAdd() }
            } label: {
                HStack(spacing: LarderSpacing.s) {
                    if model.isParsing {
                        ProgressView()
                    }
                    Text(ShelvesCopy.parse)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.larderPrimary)
            .disabled(model.isParsing || model.quickAddDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .listRowBackground(LarderColor.surface.raised)
    }

    private var linesSection: some View {
        Section {
            ForEach($model.pendingLines) { $line in
                DraftLineEditor(line: $line, defaultBestBy: model.now) {
                    model.pendingLines.removeAll { $0.id == line.id }
                }
            }
        }
        .listRowBackground(LarderColor.surface.raised)
    }

    private var confirmSection: some View {
        Section {
            Button(ShelvesCopy.addByHand, action: model.addBlankLine)
                .buttonStyle(.larderSecondary)
            Button {
                Task {
                    let added = await model.confirmPending()
                    if added > 0 {
                        AccessibilityNotification.Announcement(ShelvesCopy.added(added)).post()
                    }
                    if model.pendingLines.isEmpty { dismiss() }
                }
            } label: {
                Text(ShelvesCopy.addItems(model.confirmableLines.count))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.larderPrimary)
            .disabled(model.confirmableLines.isEmpty)
            Button(Copy.Action.notNow) {
                model.discardPending()
                dismiss()
            }
            .buttonStyle(.larderQuiet)
        }
        .listRowBackground(Color.clear)
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
