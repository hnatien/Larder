import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The flat, authored illustrations in the module's `Illustrations.xcassets`. Decorative: the words beside them carry
/// the meaning, so VoiceOver skips them. Callers fall back to a symbol when an illustration is not in the catalogue.
public nonisolated enum LarderIllustration: String, CaseIterable, Sendable {
    case welcome = "WelcomeHero"
    case pantry = "EmptyPantry"
    case plan = "EmptyPlan"
    case groceries = "EmptyGroceries"
    case recipes = "EmptyRecipes"
    case tonight = "EmptyTonight"

    /// Whether the catalogue holds this illustration.
    @MainActor
    public var isAvailable: Bool {
        #if canImport(UIKit)
        UIImage(named: rawValue, in: .module, with: nil) != nil
        #elseif canImport(AppKit)
        Bundle.module.image(forResource: rawValue) != nil
        #else
        false
        #endif
    }

    /// The illustration as a resizable image that keeps its aspect ratio.
    @MainActor
    public var image: some View {
        Image(rawValue, bundle: .module)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}
