import LarderCore
import LarderDesign
import SwiftUI

/// The "Adjust this week" chat: the person's requests on the right, the assistant's questions, proposed changes with
/// Apply and replan, and notices on the left, and a composer pinned above the keyboard. Present it as a sheet.
struct AdjustChatView: View {
    @Bindable var model: LedgerModel
    /// Closes the chat, then opens Settings; `nil` hides Open Settings.
    let onOpenSettings: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composerFocused: Bool
    @State private var asksForConsent = false
    @State private var scrollPosition = ScrollPosition()
    @ScaledSpacing(.l) private var gutter

    private var isDraftBlank: Bool {
        model.adjustDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        !isDraftBlank && !model.isAdjusting && !model.isPlanning
    }

    var body: some View {
        NavigationStack {
            transcript
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
                .background(LarderColor.surface.canvas)
                .navigationTitle(LedgerCopy.adjustTitle)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(LedgerCopy.newChat, systemImage: "square.and.pencil") {
                            model.startNewAdjustment()
                            composerFocused = true
                        }
                        .disabled(model.adjustThread.isEmpty || model.isAdjusting || model.isPlanning)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(LedgerCopy.done) { dismiss() }
                    }
                }
        }
        .sheet(isPresented: $asksForConsent) {
            AIConsentSheet {
                asksForConsent = false
                Task { await model.allowAIHelp() }
            } onDecline: {
                asksForConsent = false
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: model.adjustThread.last) { _, last in
            scrollToBottom()
            if let last, let announcement = announcement(for: last) {
                AccessibilityNotification.Announcement(announcement).post()
            }
        }
        .onChange(of: model.isAdjusting) { scrollToBottom() }
        .sensoryFeedback(.impact(weight: .light), trigger: model.adjustThread.count)
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollView {
            // Not lazy: a chat is short, and a lazy stack misjudges its height when anchored to the bottom.
            VStack(alignment: .leading, spacing: LarderSpacing.l) {
                if model.adjustThread.isEmpty {
                    emptyState
                }
                ForEach(rows, id: \.message.id) { row in
                    self.row(row.message, startsTurn: row.startsTurn)
                        .transition(messageTransition)
                }
                if model.isAdjusting {
                    TypingIndicator()
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, LarderSpacing.l)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(model.adjustThread.isEmpty ? .top : .bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .larderAnimation(LarderMotion.layout, value: model.adjustThread)
        .larderAnimation(LarderMotion.layout, value: model.isAdjusting)
    }

    private var messageTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.m) {
            AssistantMark()
            Text(LedgerCopy.adjustEmptyTitle)
                .font(LarderFont.display(.title2))
                .foregroundStyle(LarderColor.ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(LedgerCopy.adjustHint)
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ChipFlow {
                ForEach(LedgerCopy.adjustSuggestions, id: \.self) { suggestion in
                    ChoiceChip(suggestion, systemImage: "arrow.up.right", isSelected: false) {
                        model.adjustDraft = suggestion
                        send()
                    }
                    .disabled(model.isAdjusting || model.isPlanning)
                }
            }
            .padding(.top, LarderSpacing.xs)
        }
        .padding(.top, LarderSpacing.s)
    }

    /// Each message, and whether it is the assistant's first after the person spoke, so it carries the mark.
    /// Worked out from one copy of the thread, so a row never reads an index the thread no longer has.
    private var rows: [(message: AdjustMessage, startsTurn: Bool)] {
        let thread = model.adjustThread
        return thread.indices.map { index in
            (thread[index], !thread[index].isRequest && (index == 0 || thread[index - 1].isRequest))
        }
    }

    @ViewBuilder private func row(_ message: AdjustMessage, startsTurn: Bool) -> some View {
        switch message.content {
        case .request(let text):
            RequestBubble(text: text)
        case .question(let text):
            assistantRow(startsTurn: startsTurn) {
                assistantText(text)
                    .textSelection(.enabled)
                    .accessibilityLabel(Text(verbatim: "\(LedgerCopy.assistantAsks): \(text)"))
            }
        case .proposal(let adjustment, let state):
            assistantRow(startsTurn: startsTurn) {
                ProposalCard(model: model, adjustment: adjustment, state: state)
            }
        case .needsConsent:
            assistantRow(startsTurn: startsTurn) { consentNotice }
        case .failure(let error, let canRetry):
            assistantRow(startsTurn: startsTurn) { failureNotice(error, canRetry: canRetry) }
        case .replanned(let unmetDays):
            assistantRow(startsTurn: startsTurn) { replannedNotice(unmetDays) }
        }
    }

    /// What the assistant says, as plain text beside its mark.
    private func assistantText(_ text: String) -> some View {
        Text(text)
            .font(LarderFont.body(.body))
            .foregroundStyle(LarderColor.ink.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func assistantRow(startsTurn: Bool, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: LarderSpacing.s) {
            AssistantMark()
                .opacity(startsTurn ? 1 : 0)
            VStack(alignment: .leading, spacing: LarderSpacing.s) {
                content()
            }
            .padding(.top, LarderSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var consentNotice: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            assistantText(LedgerCopy.adjustNeedsConsent)
            AdaptiveStack(spacing: LarderSpacing.s, stacksFrom: .xLarge) {
                Button(Copy.Consent.allow) { asksForConsent = true }
                    .buttonStyle(.larderSecondary)
                if let onOpenSettings {
                    Button(LedgerCopy.openSettings, action: onOpenSettings)
                        .buttonStyle(.larderQuiet)
                }
            }
        }
    }

    private func failureNotice(_ error: LarderError, canRetry: Bool) -> some View {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            assistantText(LedgerCopy.adjustMessage(for: error))
            if canRetry {
                Button(Copy.App.tryAgain, systemImage: "arrow.clockwise") {
                    Task { await model.retryAdjustment() }
                }
                .buttonStyle(.larderQuiet)
                .disabled(model.isAdjusting || model.isPlanning)
            } else if error == .plusRequired {
                Button(Copy.Plus.subscribe) { model.paywallRequested = true }
                    .buttonStyle(.larderSecondary)
            }
        }
    }

    private func replannedNotice(_ unmetDays: [Date]) -> some View {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            Label {
                Text(LedgerCopy.weekReplanned)
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(LarderColor.status(.success))
            }
            if !unmetDays.isEmpty {
                Notice(text: LedgerCopy.unmetDays(unmetDays.map(Self.weekday).formatted(.list(type: .and))))
            }
            Button(LedgerCopy.seeTheWeek) { dismiss() }
                .buttonStyle(.larderQuiet)
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: LarderSpacing.s) {
            TextField(LedgerCopy.adjustTitle, text: $model.adjustDraft, prompt: Text(LedgerCopy.adjustComposerPrompt), axis: .vertical)
                .lineLimit(1...5)
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.primary)
                .padding(.vertical, LarderSpacing.s + LarderSpacing.xxs)
                .padding(.leading, LarderSpacing.xs)
                .frame(minHeight: 44)
                .focused($composerFocused)
                .accessibilityIdentifier("ledger.adjust")
                .submitLabel(.send)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(LarderFont.body(.body, weight: .bold))
                    .foregroundStyle(canSend ? LarderColor.ink.onAccent : LarderColor.ink.tertiary)
                    .frame(width: 36, height: 36)
                    .background(canSend ? LarderColor.accent.brand : LarderColor.surface.sunken, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(LedgerCopy.adjustAsk)
            .larderAnimation(LarderMotion.tap, value: canSend)
        }
        .padding(.leading, LarderSpacing.m)
        .padding(.trailing, LarderSpacing.xxs)
        .background(LarderColor.surface.raised, in: RoundedRectangle(cornerRadius: LarderRadius.sheet, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LarderRadius.sheet, style: .continuous)
                .strokeBorder(composerFocused ? LarderColor.line.strong : LarderColor.line.hairline, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { composerFocused = true }
        .padding(.horizontal, gutter)
        .padding(.top, LarderSpacing.s)
        .padding(.bottom, LarderSpacing.s)
        .background(LarderColor.surface.canvas)
        .larderAnimation(LarderMotion.tap, value: composerFocused)
    }

    private func send() {
        guard canSend else { return }
        Task { await model.requestAdjustment() }
    }

    private func scrollToBottom() {
        withAnimation(LarderMotion.resolved(LarderMotion.layout, reduceMotion: reduceMotion)) {
            scrollPosition.scrollTo(edge: .bottom)
        }
    }

    /// What VoiceOver says when a message arrives; the person's own requests are not read back.
    private func announcement(for message: AdjustMessage) -> String? {
        switch message.content {
        case .request: nil
        case .question(let text): "\(LedgerCopy.assistantAsks): \(text)"
        case .proposal(_, .pending): LedgerCopy.proposalTitle
        case .proposal: nil
        case .needsConsent: LedgerCopy.adjustNeedsConsent
        case .failure(let error, _): LedgerCopy.adjustMessage(for: error)
        case .replanned: LedgerCopy.weekReplanned
        }
    }

    private static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide))
    }
}

/// The person's request, right-aligned in a soft bubble.
private struct RequestBubble: View {
    let text: String
    @ScaledSpacing(.xxxl) private var leadingRoom

    var body: some View {
        Text(text)
            .font(LarderFont.body(.body))
            .foregroundStyle(LarderColor.ink.primary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(.horizontal, LarderSpacing.m + LarderSpacing.xxs)
            .padding(.vertical, LarderSpacing.s + LarderSpacing.xxs)
            .background(LarderColor.surface.sunken, in: RoundedRectangle(cornerRadius: LarderRadius.panel, style: .continuous))
            .padding(.leading, leadingRoom)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// The proposed changes, with Apply and replan and Not now while they wait, and what became of them after.
private struct ProposalCard: View {
    let model: LedgerModel
    let adjustment: WeekAdjustment
    let state: AdjustMessage.ProposalState

    private var isSettled: Bool { state != .pending }

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: LarderSpacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: LarderSpacing.s) {
                    Text(LedgerCopy.proposalTitle)
                        .font(LarderFont.body(.subheadline, weight: .semibold))
                        .foregroundStyle(LarderColor.ink.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    stateBadge
                }
                ForEach(adjustment.items, id: \.self) { item in
                    Label {
                        Text(LedgerCopy.describe(item, dayName: dayName))
                            .font(LarderFont.body(.body))
                            .foregroundStyle(isSettled ? LarderColor.ink.secondary : LarderColor.ink.primary)
                            .strikethrough(state == .dismissed, color: LarderColor.ink.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(isSettled ? LarderColor.ink.tertiary : LarderColor.accent.second)
                    }
                }
                if adjustment.setAsideCount > 0 {
                    Notice(text: LedgerCopy.setAside(adjustment.setAsideCount))
                }
                if state == .pending {
                    actions
                        .padding(.top, LarderSpacing.xs)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var stateBadge: some View {
        switch state {
        case .pending: EmptyView()
        case .applied: Pill(LedgerCopy.proposalApplied, systemImage: "checkmark", tone: .second)
        case .dismissed: Pill(LedgerCopy.proposalDismissed)
        case .superseded:
            Text(LedgerCopy.proposalSuperseded)
                .font(LarderFont.body(.footnote))
                .foregroundStyle(LarderColor.ink.tertiary)
        }
    }

    private var actions: some View {
        AdaptiveStack(spacing: LarderSpacing.m) {
            if !adjustment.isEmpty {
                Button {
                    Task { await model.applyAdjustment() }
                } label: {
                    HStack(spacing: LarderSpacing.s) {
                        if model.isPlanning {
                            ProgressView()
                        }
                        Text(LedgerCopy.applyAndReplan)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.larderPrimary)
                .disabled(model.isPlanning || model.isAdjusting)
            }
            Button(Copy.Action.notNow, action: model.dismissProposal)
                .buttonStyle(.larderQuiet)
                .disabled(model.isPlanning)
        }
    }

    private func dayName(_ offset: Int) -> String {
        model.adjustmentDay(offset).map { $0.formatted(.dateTime.weekday(.wide)) } ?? ""
    }
}

/// An informational line with its icon.
private struct Notice: View {
    let text: String

    var body: some View {
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
}

/// The assistant at work: an ellipsis that pulses, or holds still under Reduce Motion.
private struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: LarderSpacing.s) {
            AssistantMark()
            Image(systemName: "ellipsis")
                .font(LarderFont.body(.title3, weight: .bold))
                .foregroundStyle(LarderColor.ink.secondary)
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating, isActive: !reduceMotion)
                .padding(.horizontal, LarderSpacing.m)
                .padding(.vertical, LarderSpacing.s)
                .background(LarderColor.surface.sunken, in: Capsule())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LedgerCopy.adjusting)
    }
}
