import LarderCore
import LarderDesign
import SwiftUI

/// The plan's inline notice: the shared banner with the plan's own wording, and Try again when `onRetry` is given.
struct LedgerNotice: View {
    let error: LarderError
    var onRetry: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        InlineBanner(
            LedgerCopy.message(for: error),
            tone: Self.tone(for: error),
            action: onRetry.map { InlineBanner.Action(title: LedgerCopy.tryAgain, perform: $0) },
            dismissTitle: LedgerCopy.dismiss,
            onDismiss: onDismiss
        )
    }

    /// Assistant hiccups are information, since the plan is unharmed; anything else did not happen.
    static func tone(for error: LarderError) -> InlineBanner.Tone {
        switch error {
        case .notFound, .storageFailure: .problem
        case .assistantUnavailable, .quotaExceeded, .invalidResponse, .declined, .consentRequired, .plusRequired: .info
        }
    }
}

#if DEBUG
#Preview("LedgerNotice") {
    VStack(alignment: .leading, spacing: LarderSpacing.l) {
        LedgerNotice(error: .assistantUnavailable) {}
        LedgerNotice(error: .storageFailure, onRetry: {}) {}
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
#endif
