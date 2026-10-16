import Foundation

/// Every colour token; the raw value is the asset name in `Colors.xcassets`.
public nonisolated enum LarderToken: String, CaseIterable, Sendable {
    case surfaceCanvas = "surface.canvas"
    case surfaceRaised = "surface.raised"
    case surfaceSunken = "surface.sunken"
    case lineHairline = "line.hairline"
    case lineStrong = "line.strong"
    case inkPrimary = "ink.primary"
    case inkSecondary = "ink.secondary"
    case inkTertiary = "ink.tertiary"
    case inkOnAccent = "ink.onAccent"
    case accentBrand = "accent.brand"
    case accentSecond = "accent.second"
    case accentSpot = "accent.spot"
    case statusSuccess = "status.success"
    case statusWarning = "status.warning"
    case statusDanger = "status.danger"
    case statusInfo = "status.info"
    case foodProduce = "food.produce"
    case foodGrains = "food.grains"
    case foodProtein = "food.protein"
    case foodDairy = "food.dairy"
    case foodFats = "food.fats"
    case foodLegumes = "food.legumes"
}

/// The raw hex table behind `Colors.xcassets`, for contrast maths without rendering.
public nonisolated enum LarderPaletteHex {
    /// A token's light and dark values as `#RRGGBB`.
    public struct Pair: Sendable, Equatable {
        public let light: String
        public let dark: String

        init(_ light: String, _ dark: String) {
            self.light = light
            self.dark = dark
        }
    }

    /// Standard-contrast values for every token.
    public static let standard: [LarderToken: Pair] = [
        .surfaceCanvas: Pair("#F5F1E6", "#161915"),
        .surfaceRaised: Pair("#FFFDF7", "#20241E"),
        .surfaceSunken: Pair("#EBE5D4", "#10120F"),
        .lineHairline: Pair("#D6CEB8", "#363B32"),
        .lineStrong: Pair("#8C8570", "#7C7866"),
        .inkPrimary: Pair("#1F2620", "#F0ECDD"),
        .inkSecondary: Pair("#4F5448", "#BDBAA8"),
        .inkTertiary: Pair("#5F6256", "#9A9885"),
        .inkOnAccent: Pair("#FFFFFF", "#161915"),
        .accentBrand: Pair("#A83F18", "#F0875A"),
        .accentSecond: Pair("#2C6B5B", "#6FC0A8"),
        .accentSpot: Pair("#E3A82B", "#E3A82B"),
        .statusSuccess: Pair("#2F6B34", "#8FCB84"),
        .statusWarning: Pair("#8A5700", "#E5B04A"),
        .statusDanger: Pair("#9C1F43", "#EE8CA6"),
        .statusInfo: Pair("#2F5D7C", "#8DB9D8"),
        .foodProduce: Pair("#4A8A3C", "#86C46F"),
        .foodGrains: Pair("#B07F1E", "#E0AE4A"),
        .foodProtein: Pair("#3E6F8E", "#78AECF"),
        .foodDairy: Pair("#B05A78", "#E48FAE"),
        .foodFats: Pair("#76772A", "#B9BA52"),
        .foodLegumes: Pair("#8A5A3A", "#C99572"),
    ]

    /// Increased-contrast overrides: 10 points of HSL lightness darker in light mode, lighter in dark mode.
    public static let highContrast: [LarderToken: Pair] = [
        .lineStrong: Pair("#706A59", "#969280"),
        .inkTertiary: Pair("#45473E", "#B1B0A1"),
    ]
}

/// WCAG 2 contrast maths on `#RRGGBB` strings.
public nonisolated enum WCAGContrast {
    /// Relative luminance of an sRGB hex colour, or nil when the string is not `#RRGGBB`.
    public static func relativeLuminance(_ hex: String) -> Double? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        func linear(_ channel: UInt32) -> Double {
            let c = Double(channel) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = linear((value >> 16) & 0xFF)
        let g = linear((value >> 8) & 0xFF)
        let b = linear(value & 0xFF)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Contrast ratio between two hex colours, from 1 to 21, or nil when either is malformed.
    public static func ratio(_ hexA: String, _ hexB: String) -> Double? {
        guard let a = relativeLuminance(hexA), let b = relativeLuminance(hexB) else { return nil }
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
