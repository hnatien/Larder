import LarderDesign
import SwiftUI

/// The transient bar that offers to reverse the last removal.
struct UndoBar: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let action: UndoAction
    let onUndo: () -> Void

    var body: some View {
        PaperCard {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: LarderSpacing.s))
                : AnyLayout(HStackLayout(spacing: LarderSpacing.m))
            layout {
                Text(ShelvesCopy.removed(action))
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(ShelvesCopy.undo, action: onUndo)
                    .buttonStyle(.larderQuiet)
            }
        }
        .accessibilityElement(children: .contain)
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
