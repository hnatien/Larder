import LarderCore
import LarderDesign
import SwiftUI

/// The pantry's inline error: the shared banner with the pantry's own wording.
struct ErrorBanner: View {
    let error: LarderError
    let onDismiss: () -> Void

    var body: some View {
        InlineBanner(ShelvesCopy.message(for: error), dismissTitle: ShelvesCopy.dismiss, onDismiss: onDismiss)
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
