import LarderDesign
import SwiftUI

/// The transient toast that offers to reverse the last removal.
struct UndoBar: View {
    let action: UndoAction
    let onUndo: () -> Void

    var body: some View {
        ToastBar(
            ShelvesCopy.removed(action),
            systemImage: action.kind == .eaten ? "checkmark.circle.fill" : "trash.circle.fill",
            actionTitle: ShelvesCopy.undo,
            action: onUndo
        )
    }
}

#if DEBUG
#Preview("UndoBar") {
    VStack(spacing: LarderSpacing.l) {
        UndoBar(action: UndoAction(item: PreviewData.items()[0], kind: .eaten)) {}
        UndoBar(action: UndoAction(item: PreviewData.items()[1], kind: .letGo)) {}
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
#endif
