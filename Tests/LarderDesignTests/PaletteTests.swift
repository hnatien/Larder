import Foundation
import Testing
@testable import LarderDesign

/// The blueprint section 7 table, typed out independently of the module's own table.
private let blueprintHex: [String: (light: String, dark: String)] = [
    "surface.canvas": ("#F5F1E6", "#161915"),
    "surface.raised": ("#FFFDF7", "#20241E"),
    "surface.sunken": ("#EBE5D4", "#10120F"),
    "line.hairline": ("#D6CEB8", "#363B32"),
    "line.strong": ("#8C8570", "#7C7866"),
    "ink.primary": ("#1F2620", "#F0ECDD"),
    "ink.secondary": ("#4F5448", "#BDBAA8"),
    "ink.tertiary": ("#5F6256", "#9A9885"),
    "ink.onAccent": ("#FFFFFF", "#161915"),
    "accent.brand": ("#A83F18", "#F0875A"),
    "accent.second": ("#2C6B5B", "#6FC0A8"),
    "accent.spot": ("#E3A82B", "#E3A82B"),
    "status.success": ("#2F6B34", "#8FCB84"),
    "status.warning": ("#8A5700", "#E5B04A"),
    "status.danger": ("#9C1F43", "#EE8CA6"),
    "status.info": ("#2F5D7C", "#8DB9D8"),
    "food.produce": ("#4A8A3C", "#86C46F"),
    "food.grains": ("#B07F1E", "#E0AE4A"),
    "food.protein": ("#3E6F8E", "#78AECF"),
    "food.dairy": ("#B05A78", "#E48FAE"),
    "food.fats": ("#76772A", "#B9BA52"),
    "food.legumes": ("#8A5A3A", "#C99572"),
]

private struct ColorSetVariants {
    var light: String?
    var dark: String?
    var lightHighContrast: String?
    var darkHighContrast: String?
}

private func parseColorSet(named name: String) throws -> ColorSetVariants {
    let url = DesignSources.colors.appending(path: "\(name).colorset/Contents.json")
    let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let entries = try #require(root["colors"] as? [[String: Any]])
    var variants = ColorSetVariants()
    for entry in entries {
        let color = try #require(entry["color"] as? [String: Any])
        #expect(color["color-space"] as? String == "srgb", "\(name) must be sRGB")
        let components = try #require(color["components"] as? [String: String])
        #expect(components["alpha"].flatMap(Double.init) == 1, "\(name) must be opaque")
        let channels = try ["red", "green", "blue"].map { key -> String in
            let raw = try #require(components[key], "\(name) missing \(key)")
            #expect(raw.hasPrefix("0x"), "\(name) \(key) must be written as 0x..")
            let value = try #require(UInt8(raw.dropFirst(2), radix: 16))
            return String(format: "%02X", value)
        }
        let hex = "#" + channels.joined()
        let appearances = (entry["appearances"] as? [[String: String]] ?? [])
            .reduce(into: [String: String]()) { $0[$1["appearance"] ?? ""] = $1["value"] }
        let isDark = appearances["luminosity"] == "dark"
        let isHigh = appearances["contrast"] == "high"
        switch (isDark, isHigh) {
        case (false, false): variants.light = hex
        case (true, false): variants.dark = hex
        case (false, true): variants.lightHighContrast = hex
        case (true, true): variants.darkHighContrast = hex
        }
    }
    return variants
}

@Suite("Palette")
struct PaletteTests {
    @Test func blueprintTableCoversEveryToken() {
        #expect(Set(blueprintHex.keys) == Set(LarderToken.allCases.map(\.rawValue)))
    }

    @Test func assetCatalogueHoldsExactlyTheTokens() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: DesignSources.colors.path)
            .filter { $0.hasSuffix(".colorset") }
            .map { String($0.dropLast(".colorset".count)) }
        #expect(Set(names) == Set(blueprintHex.keys))
        #expect(names.count == 22)
    }

    @Test(arguments: LarderToken.allCases)
    func contentsJSONMatchesBlueprint(token: LarderToken) throws {
        let expected = try #require(blueprintHex[token.rawValue])
        let variants = try parseColorSet(named: token.rawValue)
        #expect(variants.light == expected.light, "\(token.rawValue) light")
        #expect(variants.dark == expected.dark, "\(token.rawValue) dark")
    }

    @Test(arguments: LarderToken.allCases)
    func hexTableMatchesBlueprint(token: LarderToken) throws {
        let expected = try #require(blueprintHex[token.rawValue])
        let pair = try #require(LarderPaletteHex.standard[token])
        #expect(pair.light == expected.light)
        #expect(pair.dark == expected.dark)
    }

    @Test func hexTableHasNoStrayTokens() {
        #expect(Set(LarderPaletteHex.standard.keys) == Set(LarderToken.allCases))
    }

    @Test(arguments: LarderToken.allCases)
    func highContrastVariantsExistOnlyWhereDeclared(token: LarderToken) throws {
        let variants = try parseColorSet(named: token.rawValue)
        if let pair = LarderPaletteHex.highContrast[token] {
            #expect(variants.lightHighContrast == pair.light, "\(token.rawValue) light high contrast")
            #expect(variants.darkHighContrast == pair.dark, "\(token.rawValue) dark high contrast")
        } else {
            #expect(variants.lightHighContrast == nil)
            #expect(variants.darkHighContrast == nil)
        }
    }

    @Test func highContrastTokensAreLineStrongAndInkTertiary() {
        #expect(Set(LarderPaletteHex.highContrast.keys) == [.lineStrong, .inkTertiary])
    }

    @Test(arguments: [LarderToken.lineStrong, .inkTertiary])
    func highContrastShiftsLightnessByTenPoints(token: LarderToken) throws {
        let base = try #require(LarderPaletteHex.standard[token])
        let high = try #require(LarderPaletteHex.highContrast[token])
        let lightShift = try hslLightness(high.light) - hslLightness(base.light)
        let darkShift = try hslLightness(high.dark) - hslLightness(base.dark)
        #expect(abs(lightShift + 0.10) < 0.005, "light mode darkens by 10 points, got \(lightShift)")
        #expect(abs(darkShift - 0.10) < 0.005, "dark mode lightens by 10 points, got \(darkShift)")
    }

    @Test func noPaletteColourSitsInThePurpleOrIndigoBand() throws {
        for (token, pair) in LarderPaletteHex.standard {
            for hex in [pair.light, pair.dark] {
                let (hue, saturation) = try hueAndSaturation(hex)
                let chromatic = saturation > 0.15
                #expect(!(chromatic && (250...300).contains(hue)), "\(token.rawValue) \(hex) hue \(hue)")
            }
        }
    }

    private func channels(_ hex: String) throws -> (Double, Double, Double) {
        let value = try #require(UInt32(hex.dropFirst(), radix: 16))
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    private func hslLightness(_ hex: String) throws -> Double {
        let (r, g, b) = try channels(hex)
        return (max(r, g, b) + min(r, g, b)) / 2
    }

    private func hueAndSaturation(_ hex: String) throws -> (hue: Double, saturation: Double) {
        let (r, g, b) = try channels(hex)
        let high = max(r, g, b)
        let low = min(r, g, b)
        let delta = high - low
        guard delta > 0 else { return (0, 0) }
        let lightness = (high + low) / 2
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch high {
        case r: hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        case g: hue = (b - r) / delta + 2
        default: hue = (r - g) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, saturation)
    }
}
