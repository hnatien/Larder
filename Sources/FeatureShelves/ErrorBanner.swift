import LarderCore
import LarderDesign
import SwiftUI

/// An inline error: icon, plain sentence and a dismiss button. Colour is never the only signal.
struct ErrorBanner: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let error: LarderError
    let onDismiss: () -> Void

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LarderSpacing.s))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: LarderSpacing.m))
        layout {
            Label {
                Text(ShelvesCopy.message(for: error))
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(LarderColor.status(.danger))
            }
            Button(ShelvesCopy.dismiss, action: onDismiss)
                .buttonStyle(.larderQuiet)
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("ErrorBanner") {
    VStack(alignment: .leading, spacing: LarderSpacing.l) {
        ErrorBanner(error: .consentRequired) {}
        ErrorBanner(error: .storageFailure) {}
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
