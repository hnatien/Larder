import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private struct LarderTheme: ViewModifier {
    init() {
        LarderFont.registerBundledFonts()
        LarderTheme.styleNavigationBars()
    }

    func body(content: Content) -> some View {
        content
            .tint(LarderColor.accent.brand)
            .background(LarderColor.surface.canvas)
    }

    /// Fraunces for every navigation title, large and inline, so all tabs share one title voice. The bars stay
    /// system glass; only the title font and ink change.
    @MainActor
    static func styleNavigationBars() {
        #if canImport(UIKit) && !os(watchOS)
        guard LarderFont.hasBundledFonts else { return }
        let ink = UIColor(named: LarderToken.inkPrimary.rawValue, in: .module, compatibleWith: nil) ?? .label
        let bar = UINavigationBar.appearance()
        if let large = UIFont(name: LarderFont.displaySpec(for: .largeTitle).postScriptName, size: 34) {
            bar.largeTitleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large),
                .foregroundColor: ink,
            ]
        }
        if let inline = UIFont(name: LarderFont.displaySpec(for: .headline).postScriptName, size: 17) {
            bar.titleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline),
                .foregroundColor: ink,
            ]
        }
        #endif
    }
}

public extension View {
    /// Applies the paper canvas, the brand tint and the title font, and registers bundled fonts once. Apply at the root.
    func larderTheme() -> some View {
        modifier(LarderTheme())
    }

    /// Draws a `List` or `Form` on the paper canvas instead of the system background.
    func larderList() -> some View {
        scrollContentBackground(.hidden)
            .background(LarderColor.surface.canvas)
    }

    /// An inset grouped list on the paper canvas, its rows on raised paper.
    func larderGroupedList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped).larderList()
        #else
        listStyle(.inset).larderList()
        #endif
    }
}

public extension View {
    /// The Settings button, in the same corner on every tab root; nothing when `action` is `nil`.
    func settingsButton(_ action: (() -> Void)?) -> some View {
        toolbar {
            if let action {
                ToolbarItem(placement: .navigation) {
                    Button(Copy.Tab.account, systemImage: "gearshape", action: action)
                }
            }
        }
    }
}

public extension EnvironmentValues {
    /// Whether a finished cooking timer flashes the screen and vibrates as well as announcing itself.
    @Entry var timersFlashAndVibrate = true
}
