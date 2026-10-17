import LarderCore
import LarderDesign
import SwiftUI

/// "Adjust this week": a request in plain words, the assistant's proposed changes or question, and Apply and replan.
struct AdjustWeekCard: View {
    @Bindable var model: LedgerModel
    let onOpenSettings: (() -> Void)?
    @FocusState private var fieldFocused: Bool

    private var isDraftBlank: Bool {
        model.adjustDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: LarderSpacing.m) {
                Text(LedgerCopy.adjustTitle)
                    .font(LarderFont.body(.headline, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.primary)
                    .accessibilityAddTraits(.isHeader)
                field
                Text(LedgerCopy.adjustHint)
                    .font(LarderFont.body(.footnote))
                    .foregroundStyle(LarderColor.ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.isAdjusting {
                    HStack(spacing: LarderSpacing.s) {
                        ProgressView()
                        Text(LedgerCopy.adjusting)
                            .font(LarderFont.body(.body))
                            .foregroundStyle(LarderColor.ink.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if model.adjustNeedsConsent {
                    consentNote
                }
                if let error = model.adjustError {
                    note(LedgerCopy.adjustMessage(for: error))
                }
                if let question = model.adjustQuestion {
                    VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                        Text(LedgerCopy.assistantAsks)
                            .font(LarderFont.body(.subheadline, weight: .semibold))
                            .foregroundStyle(LarderColor.ink.secondary)
                        Text(question)
                            .font(LarderFont.body(.body))
                            .foregroundStyle(LarderColor.ink.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let proposal = model.proposedAdjustment {
                    proposalView(proposal)
                }
                if !model.unmetAdjustmentDays.isEmpty {
                    note(LedgerCopy.unmetDays(model.unmetAdjustmentDays.map(Self.weekday).formatted(.list(type: .and))))
                }
            }
        }
        .onChange(of: model.adjustQuestion) { _, question in
            if let question { AccessibilityNotification.Announcement(question).post() }
        }
        .onChange(of: model.proposedAdjustment) { _, proposal in
            if proposal != nil { AccessibilityNotification.Announcement(LedgerCopy.proposalTitle).post() }
        }
        .onChange(of: model.adjustError) { _, error in
            if let error { AccessibilityNotification.Announcement(LedgerCopy.adjustMessage(for: error)).post() }
        }
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            TextField(LedgerCopy.adjustTitle, text: $model.adjustDraft, prompt: Text(LedgerCopy.adjustPrompt), axis: .vertical)
                .lineLimit(1...4)
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.primary)
                .padding(LarderSpacing.m)
                .frame(minHeight: 44)
                .background(LarderColor.surface.raised, in: RoundedRectangle(cornerRadius: LarderRadius.field))
                .overlay {
                    RoundedRectangle(cornerRadius: LarderRadius.field)
                        .strokeBorder(LarderColor.line.strong, lineWidth: 1)
                }
                .focused($fieldFocused)
                .accessibilityIdentifier("ledger.adjust")
                .submitLabel(.send)
                .onSubmit(ask)
            Button(action: ask) {
                Text(LedgerCopy.adjustAsk)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.larderSecondary)
                .disabled(isDraftBlank || model.isAdjusting || model.isPlanning)
        }
    }

    private var consentNote: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            note(LedgerCopy.adjustNeedsConsent)
            if let onOpenSettings {
                Button(LedgerCopy.openSettings, action: onOpenSettings)
                    .buttonStyle(.larderQuiet)
            }
        }
    }

    private func proposalView(_ proposal: WeekAdjustment) -> some View {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            if !proposal.isEmpty {
                Text(LedgerCopy.proposalTitle)
                    .font(LarderFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.secondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(proposal.items, id: \.self) { item in
                    Label {
                        Text(LedgerCopy.describe(item, dayName: dayName))
                            .font(LarderFont.body(.body))
                            .foregroundStyle(LarderColor.ink.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(LarderColor.accent.second)
                    }
                }
            }
            if proposal.setAsideCount > 0 {
                note(LedgerCopy.setAside(proposal.setAsideCount))
            }
            AdaptiveStack(spacing: LarderSpacing.m) {
                if !proposal.isEmpty {
                    Button {
                        Task { await model.applyAdjustment() }
                    } label: {
                        Text(LedgerCopy.applyAndReplan)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.larderPrimary)
                    .disabled(model.isPlanning)
                }
                Button(Copy.Action.notNow, action: model.dismissAdjustment)
                    .buttonStyle(.larderQuiet)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Label {
            Text(text)
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.primary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(LarderColor.status(.info))
        }
    }

    private func ask() {
        guard !isDraftBlank else { return }
        fieldFocused = false
        Task { await model.requestAdjustment() }
    }

    private func dayName(_ offset: Int) -> String {
        model.adjustmentDay(offset).map(Self.weekday) ?? ""
    }

    private static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide))
    }
}
