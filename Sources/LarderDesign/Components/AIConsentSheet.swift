import SwiftUI

/// Asks for AI help where it is needed, instead of sending the user to Settings: what is sent, what never leaves the
/// device, and Allow or Not now with equal weight. Present it as a sheet.
public struct AIConsentSheet: View {
    private let onAllow: () -> Void
    private let onDecline: () -> Void

    /// Creates the sheet; exactly one of the two actions runs, and the presenter dismisses it.
    public init(onAllow: @escaping () -> Void, onDecline: @escaping () -> Void) {
        self.onAllow = onAllow
        self.onDecline = onDecline
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LarderSpacing.l) {
                Image(systemName: "sparkles")
                    .font(LarderFont.body(.title2, weight: .semibold))
                    .foregroundStyle(LarderColor.accent.brand)
                    .accessibilityHidden(true)
                Text(Copy.Consent.title)
                    .font(LarderFont.display(.title2))
                    .foregroundStyle(LarderColor.ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: LarderSpacing.m) {
                    point(Copy.Consent.sends, systemImage: "arrow.up.doc")
                    point(Copy.Consent.stays, systemImage: "lock")
                    point(Copy.Consent.change, systemImage: "gearshape")
                }
                AdaptiveStack(spacing: LarderSpacing.s, stacksFrom: .xLarge) {
                    Button(action: onAllow) {
                        Text(Copy.Consent.allow).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.larderPrimary)
                    Button(action: onDecline) {
                        Text(Copy.Action.notNow).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.larderSecondary)
                }
            }
            .padding(LarderSpacing.l)
        }
        .background(LarderColor.surface.canvas)
    }

    private func point(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.primary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(LarderColor.accent.second)
        }
    }
}

#Preview("AIConsentSheet") {
    AIConsentSheet(onAllow: {}, onDecline: {})
}
