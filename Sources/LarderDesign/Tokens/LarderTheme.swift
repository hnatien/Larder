import SwiftUI

private struct LarderTheme: ViewModifier {
    init() {
        LarderFont.registerBundledFonts()
    }

    func body(content: Content) -> some View {
        content
            .tint(LarderColor.accent.brand)
            .background(LarderColor.surface.canvas)
    }
}

public extension View {
    /// Applies the paper canvas and the brand tint, and registers bundled fonts once. Apply at the root.
    func larderTheme() -> some View {
        modifier(LarderTheme())
    }

    /// Draws a `List` or `Form` on the paper canvas instead of the system background.
    func larderList() -> some View {
        scrollContentBackground(.hidden)
            .background(LarderColor.surface.canvas)
    }
}
