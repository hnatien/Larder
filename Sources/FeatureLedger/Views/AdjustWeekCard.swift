import LarderCore
import LarderDesign
import SwiftUI

/// "Adjust this week" on the Plan tab: one row that opens the chat, showing where the chat left off.
struct AdjustWeekCard: View {
    let model: LedgerModel
    let onOpen: () -> Void

    /// The latest thing said in the chat, else an example request.
    private var preview: String {
        guard let last = model.adjustThread.last else { return LedgerCopy.adjustPrompt }
        return switch last.content {
        case .request(let text), .question(let text): text
        case .proposal: LedgerCopy.proposalTitle
        case .needsConsent: LedgerCopy.adjustNeedsConsent
        case .failure(let error, _): LedgerCopy.adjustMessage(for: error)
        case .replanned: LedgerCopy.weekReplanned
        }
    }

    var body: some View {
        Button(action: onOpen) {
            PaperCard {
                HStack(spacing: LarderSpacing.m) {
                    AssistantMark()
                    VStack(alignment: .leading, spacing: LarderSpacing.xxs) {
                        // Plain text, not a Label, so it wraps at the largest sizes instead of clipping.
                        Text(LedgerCopy.adjustTitle)
                            .font(LarderFont.body(.headline, weight: .semibold))
                            .foregroundStyle(LarderColor.ink.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(preview)
                            .font(LarderFont.body(.subheadline))
                            .foregroundStyle(LarderColor.ink.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if model.pendingAdjustment != nil {
                        Pill(LedgerCopy.proposalTitle, tone: .spot)
                            .accessibilityHidden(true)
                    }
                    Image(systemName: "chevron.right")
                        .font(LarderFont.body(.subheadline, weight: .semibold))
                        .foregroundStyle(LarderColor.ink.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LedgerCopy.adjustTitle)
        .accessibilityValue(preview)
    }
}

/// The assistant's mark beside its messages and on the Plan tab row.
struct AssistantMark: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 28

    var body: some View {
        Image(systemName: "text.bubble")
            .font(LarderFont.body(.footnote, weight: .semibold))
            .foregroundStyle(LarderColor.accent.second)
            .frame(width: size, height: size)
            .background(LarderColor.accent.second.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}
