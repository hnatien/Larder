import LarderCore
import SwiftUI

/// Larder's colour tokens, backed by `Colors.xcassets` so light, dark and increased contrast resolve from the system.
public enum LarderColor {
    /// Resolves a token from the module's asset catalogue.
    public static func color(_ token: LarderToken) -> Color {
        Color(token.rawValue, bundle: .module)
    }

    /// Paper, card and well surfaces.
    public struct Surface {
        public let canvas = LarderColor.color(.surfaceCanvas)
        public let raised = LarderColor.color(.surfaceRaised)
        public let sunken = LarderColor.color(.surfaceSunken)
    }

    /// Hairline rules and strong outlines.
    public struct Line {
        public let hairline = LarderColor.color(.lineHairline)
        public let strong = LarderColor.color(.lineStrong)
    }

    /// Text and icon colours.
    public struct Ink {
        public let primary = LarderColor.color(.inkPrimary)
        public let secondary = LarderColor.color(.inkSecondary)
        public let tertiary = LarderColor.color(.inkTertiary)
        public let onAccent = LarderColor.color(.inkOnAccent)
    }

    /// Paprika, verdigris and mustard.
    public struct Accent {
        public let brand = LarderColor.color(.accentBrand)
        public let second = LarderColor.color(.accentSecond)
        /// Fill only; never text.
        public let spot = LarderColor.color(.accentSpot)
    }

    public static let surface = Surface()
    public static let line = Line()
    public static let ink = Ink()
    public static let accent = Accent()

    /// A status tone; always pair it with an icon and a word.
    public static func status(_ status: Status) -> Color {
        color(status.token)
    }

    /// The colour for a food group; `.other` has no hue of its own and uses the strong line.
    public static func food(_ group: FoodGroup) -> Color {
        switch group {
        case .produce: color(.foodProduce)
        case .grains: color(.foodGrains)
        case .protein: color(.foodProtein)
        case .dairy: color(.foodDairy)
        case .fats: color(.foodFats)
        case .legumes: color(.foodLegumes)
        case .other: color(.lineStrong)
        }
    }

    /// Status tones.
    public enum Status: CaseIterable {
        case success, warning, danger, info

        var token: LarderToken {
            switch self {
            case .success: .statusSuccess
            case .warning: .statusWarning
            case .danger: .statusDanger
            case .info: .statusInfo
            }
        }
    }
}
