import LarderCore
import LarderDesign
import SwiftUI

/// An inline notice: icon, plain sentence and a dismiss button. Never red; the ledger has no failure state.
struct LedgerNotice: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let error: LarderError
    let onDismiss: () -> Void

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LarderSpacing.s))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: LarderSpacing.m))
        layout {
            Label {
                Text(LedgerCopy.message(for: error))
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(LarderColor.status(.info))
            }
            Button(LedgerCopy.dismiss, action: onDismiss)
                .buttonStyle(.larderQuiet)
        }
        .padding(LarderSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LarderColor.status(.info).opacity(0.08), in: RoundedRectangle(cornerRadius: LarderRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("LedgerNotice") {
    VStack(alignment: .leading, spacing: LarderSpacing.l) {
        LedgerNotice(error: .assistantUnavailable) {}
        LedgerNotice(error: .storageFailure) {}
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
#endif
