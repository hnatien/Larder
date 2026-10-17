import LarderCore
import LarderDesign
import SwiftUI

/// The repair proposed after a skip, a day left uncooked or a lost food: each change with why, then Make these
/// changes or Not now; once applied, a note with Undo.
struct RepairCard: View {
    let model: LedgerModel

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: LarderSpacing.m) {
                if model.proposedRepair != nil {
                    proposal
                } else if model.canUndoRepair {
                    applied
                }
            }
        }
    }

    private var proposal: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.m) {
            Text(LedgerCopy.repairTitle)
                .font(LarderFont.body(.headline, weight: .semibold))
                .foregroundStyle(LarderColor.ink.primary)
                .accessibilityAddTraits(.isHeader)
            ForEach(model.repairLines) { line in
                VStack(alignment: .leading, spacing: LarderSpacing.xxs) {
                    Text(line.text)
                        .font(LarderFont.body(.body))
                        .foregroundStyle(LarderColor.ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(line.reason)
                        .font(LarderFont.body(.footnote))
                        .foregroundStyle(LarderColor.ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            AdaptiveStack(spacing: LarderSpacing.m) {
                Button {
                    Task { await model.applyRepair() }
                } label: {
                    Text(LedgerCopy.applyRepair)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.larderPrimary)
                .disabled(model.isPlanning)
                Button(Copy.Action.notNow, action: model.dismissRepair)
                    .buttonStyle(.larderQuiet)
            }
        }
    }

    private var applied: some View {
        AdaptiveStack(spacing: LarderSpacing.m) {
            Label {
                Text(LedgerCopy.repairApplied)
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark")
                    .foregroundStyle(LarderColor.accent.second)
            }
            Button(LedgerCopy.undo) { Task { await model.undoRepair() } }
                .buttonStyle(.larderQuiet)
        }
    }
}
