import Testing
@testable import LarderDesign

private enum Mode: CaseIterable {
    case light, dark

    func hex(_ token: LarderToken, highContrast: Bool = false) -> String {
        let table = highContrast ? LarderPaletteHex.highContrast : LarderPaletteHex.standard
        let pair = table[token] ?? LarderPaletteHex.standard[token]!
        return self == .light ? pair.light : pair.dark
    }
}

private let surfaces: [LarderToken] = [.surfaceCanvas, .surfaceRaised, .surfaceSunken]
private let foodTokens: [LarderToken] = [.foodProduce, .foodGrains, .foodProtein, .foodDairy, .foodFats, .foodLegumes]

private func ratio(_ foreground: String, _ background: String) -> Double {
    WCAGContrast.ratio(foreground, background) ?? 0
}

@Suite("WCAG contrast")
struct ContrastTests {
    @Test func blackOnWhiteIsTwentyOne() throws {
        #expect(try #require(WCAGContrast.ratio("#000000", "#FFFFFF")).isApproximatelyEqual(to: 21, tolerance: 0.001))
    }

    @Test func identicalColoursAreOne() throws {
        #expect(try #require(WCAGContrast.ratio("#8C8570", "#8C8570")).isApproximatelyEqual(to: 1, tolerance: 0.0001))
    }

    @Test func ratioIsSymmetric() {
        #expect(WCAGContrast.ratio("#1F2620", "#F5F1E6") == WCAGContrast.ratio("#F5F1E6", "#1F2620"))
    }

    @Test func middleGreyMatchesPublishedLuminance() throws {
        let luminance = try #require(WCAGContrast.relativeLuminance("#808080"))
        #expect(luminance.isApproximatelyEqual(to: 0.2158605, tolerance: 0.0001))
    }

    @Test func matchesResearchFigures() {
        #expect(ratio("#1F2620", "#F5F1E6").isApproximatelyEqual(to: 13.7, tolerance: 0.1))
        #expect(ratio("#FFFFFF", "#A83F18").isApproximatelyEqual(to: 6.2, tolerance: 0.1))
        #expect(ratio("#8C8570", "#F5F1E6").isApproximatelyEqual(to: 3.26, tolerance: 0.05))
    }

    @Test(arguments: ["", "#FFF", "#GGGGGG", "F5F1E6FF", "#12345"])
    func malformedHexIsRejected(hex: String) {
        #expect(WCAGContrast.relativeLuminance(hex) == nil)
        #expect(WCAGContrast.ratio(hex, "#FFFFFF") == nil)
    }

    @Test func hexWithoutHashIsAccepted() {
        #expect(WCAGContrast.ratio("FFFFFF", "000000") != nil)
    }

    @Test(arguments: Mode.allCases)
    fileprivate func inkReadsOnEverySurface(mode: Mode) {
        for ink in [LarderToken.inkPrimary, .inkSecondary, .inkTertiary] {
            for surface in surfaces {
                let value = ratio(mode.hex(ink), mode.hex(surface))
                #expect(value >= 4.5, "\(ink.rawValue) on \(surface.rawValue) \(mode): \(value)")
            }
        }
    }

    @Test(arguments: Mode.allCases)
    fileprivate func accentsAndStatusReadOnEverySurface(mode: Mode) {
        let tokens: [LarderToken] = [
            .accentBrand, .accentSecond, .statusSuccess, .statusWarning, .statusDanger, .statusInfo,
        ]
        for token in tokens {
            for surface in surfaces {
                let value = ratio(mode.hex(token), mode.hex(surface))
                #expect(value >= 4.5, "\(token.rawValue) on \(surface.rawValue) \(mode): \(value)")
            }
        }
    }

    @Test(arguments: Mode.allCases)
    fileprivate func textOnAccentFillsReads(mode: Mode) {
        for fill in [LarderToken.accentBrand, .accentSecond] {
            let value = ratio(mode.hex(.inkOnAccent), mode.hex(fill))
            #expect(value >= 4.5, "ink.onAccent on \(fill.rawValue) \(mode): \(value)")
        }
    }

    @Test func spotFillCarriesLightInkInBothModes() {
        let value = ratio(LarderPaletteHex.standard[.inkPrimary]!.light, LarderPaletteHex.standard[.accentSpot]!.light)
        #expect(value >= 4.5, "light ink.primary on accent.spot: \(value)")
        #expect(LarderPaletteHex.standard[.accentSpot]!.light == LarderPaletteHex.standard[.accentSpot]!.dark)
    }

    @Test(arguments: Mode.allCases)
    fileprivate func foodColoursAreVisibleOnPaper(mode: Mode) {
        for food in foodTokens {
            for surface in [LarderToken.surfaceCanvas, .surfaceRaised] {
                let value = ratio(mode.hex(food), mode.hex(surface))
                #expect(value >= 3, "\(food.rawValue) on \(surface.rawValue) \(mode): \(value)")
            }
        }
    }

    @Test func strongLineIsVisibleOnCanvasAndOnLightRaised() {
        for mode in Mode.allCases {
            let value = ratio(mode.hex(.lineStrong), mode.hex(.surfaceCanvas))
            #expect(value >= 3, "line.strong on canvas \(mode): \(value)")
        }
        let raised = ratio(Mode.light.hex(.lineStrong), Mode.light.hex(.surfaceRaised))
        #expect(raised >= 3, "line.strong on raised light: \(raised)")
    }

    @Test func strongLineOnDarkRaisedMeetsThreeToOne() {
        let value = ratio(Mode.dark.hex(.lineStrong), Mode.dark.hex(.surfaceRaised))
        #expect(value >= 3, "line.strong on raised dark: \(value)")
    }

    @Test(arguments: Mode.allCases)
    fileprivate func highContrastVariantsOnlyImprove(mode: Mode) {
        for surface in surfaces {
            let strongBase = ratio(mode.hex(.lineStrong), mode.hex(surface))
            let strongHigh = ratio(mode.hex(.lineStrong, highContrast: true), mode.hex(surface))
            #expect(strongHigh > strongBase, "line.strong \(mode) on \(surface.rawValue)")
            let inkBase = ratio(mode.hex(.inkTertiary), mode.hex(surface))
            let inkHigh = ratio(mode.hex(.inkTertiary, highContrast: true), mode.hex(surface))
            #expect(inkHigh > inkBase, "ink.tertiary \(mode) on \(surface.rawValue)")
            #expect(inkHigh >= 4.5)
        }
    }
}

private extension Double {
    func isApproximatelyEqual(to other: Double, tolerance: Double) -> Bool {
        abs(self - other) <= tolerance
    }
}
