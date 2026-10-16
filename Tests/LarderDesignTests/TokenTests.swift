import LarderCore
import SwiftUI
import Testing
@testable import LarderDesign

@Suite("Motion")
struct MotionTests {
    @Test func durationsAreTheSpecifiedThree() {
        #expect(LarderMotion.state == 0.12)
        #expect(LarderMotion.navigation == 0.22)
        #expect(LarderMotion.sheet == 0.36)
    }

    @Test func durationsGrowWithTheSizeOfTheChange() {
        #expect(LarderMotion.state < LarderMotion.navigation)
        #expect(LarderMotion.navigation < LarderMotion.sheet)
    }

    @Test func curvesAreTheSpecifiedOnes() {
        #expect(LarderMotion.tap == .snappy(duration: 0.28))
        #expect(LarderMotion.layout == .smooth(duration: 0.4))
        #expect(LarderMotion.stamped == .bouncy)
        #expect(LarderMotion.reduced == .easeOut(duration: 0.12))
    }

    @Test(arguments: [LarderMotion.tap, LarderMotion.layout, LarderMotion.stamped])
    func reduceMotionReplacesEveryCurveWithAShortEaseOut(animation: Animation) {
        #expect(LarderMotion.resolved(animation, reduceMotion: true) == .easeOut(duration: 0.12))
        #expect(LarderMotion.resolved(animation, reduceMotion: false) == animation)
    }
}

@Suite("Spacing and radius")
struct SpacingTests {
    @Test func scaleIsTheSpecifiedNine() {
        let scale: [CGFloat] = [
            LarderSpacing.xxs, LarderSpacing.xs, LarderSpacing.s, LarderSpacing.m, LarderSpacing.l,
            LarderSpacing.xl, LarderSpacing.xxl, LarderSpacing.xxxl, LarderSpacing.huge,
        ]
        #expect(scale == [2, 4, 8, 12, 16, 24, 32, 48, 64])
    }

    @Test func stepsAreStrictlyIncreasing() {
        let points = LarderSpacing.Step.allCases.map(\.points)
        #expect(points.count == 9)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func stepsMatchTheConstants() {
        #expect(LarderSpacing.Step.m.points == LarderSpacing.m)
        #expect(LarderSpacing.Step.huge.points == LarderSpacing.huge)
    }

    @Test func radiiAreTheSpecifiedFive() {
        #expect(LarderRadius.stamp == 2)
        #expect(LarderRadius.field == 8)
        #expect(LarderRadius.card == 12)
        #expect(LarderRadius.sheet == 24)
        #expect(LarderRadius.pill == .infinity)
    }

    @Test func radiiAreStrictlyIncreasing() {
        let radii = [LarderRadius.stamp, LarderRadius.field, LarderRadius.card, LarderRadius.sheet, LarderRadius.pill]
        #expect(zip(radii, radii.dropFirst()).allSatisfy { $0 < $1 })
    }
}

@MainActor
@Suite("Typography")
struct TypographyTests {
    private let allStyles: [Font.TextStyle] = [
        .largeTitle, .title, .title2, .title3, .headline, .body, .callout, .subheadline, .footnote, .caption, .caption2,
    ]

    @Test func displayUsesOnlyTheThreeBundledInstances() {
        let names = Set(allStyles.map { LarderFont.displaySpec(for: $0).postScriptName })
        #expect(names == ["Fraunces144pt-SoftMedium", "Fraunces144pt-SoftBold", "Fraunces72pt-SoftSemiBold"])
    }

    @Test func displayStartsAtTwentyTwoPoints() {
        for style in allStyles { #expect(LarderFont.displaySpec(for: style).size >= 22, "\(style)") }
    }

    @Test func displayIsNeverLight() {
        for style in allStyles {
            let weight = LarderFont.displaySpec(for: style).weight
            #expect([Font.Weight.medium, .semibold, .bold].contains(weight), "\(style)")
        }
    }

    @Test func monoUsesCommitMonoRegular() {
        #expect(LarderFont.monoPostScriptName == "CommitMono-Regular")
    }

    @Test func stampTrackingIsFourHundredthsOfAnEm() {
        #expect(LarderFont.stampTracking == 0.04)
    }

    @Test func monoSizesFollowTheTextStyles() {
        let sizes = [Font.TextStyle.caption2, .caption, .footnote, .subheadline, .body].map(LarderFont.monoSize(for:))
        #expect(sizes == [11, 12, 13, 15, 17])
    }

    @Test func registrationReportsWhetherFontFilesAreBundled() {
        let shipped = DesignSources.files(withExtension: "ttf", under: DesignSources.resources)
            + DesignSources.files(withExtension: "otf", under: DesignSources.resources)
        #expect(LarderFont.registerBundledFonts() == !shipped.isEmpty)
        #expect(LarderFont.hasBundledFonts == !shipped.isEmpty)
        #expect(LarderFont.registerBundledFonts() == LarderFont.hasBundledFonts)
    }
}

@MainActor
@Suite("Colour access")
struct ColorAccessTests {
    @Test func foodGroupsMapToTheirOwnTokens() {
        #expect(LarderColor.food(.produce) == LarderColor.color(.foodProduce))
        #expect(LarderColor.food(.grains) == LarderColor.color(.foodGrains))
        #expect(LarderColor.food(.protein) == LarderColor.color(.foodProtein))
        #expect(LarderColor.food(.dairy) == LarderColor.color(.foodDairy))
        #expect(LarderColor.food(.fats) == LarderColor.color(.foodFats))
        #expect(LarderColor.food(.legumes) == LarderColor.color(.foodLegumes))
        #expect(LarderColor.food(.other) == LarderColor.color(.lineStrong))
    }

    @Test func statusTonesMapToTheirOwnTokens() {
        #expect(LarderColor.status(.success) == LarderColor.color(.statusSuccess))
        #expect(LarderColor.status(.warning) == LarderColor.color(.statusWarning))
        #expect(LarderColor.status(.danger) == LarderColor.color(.statusDanger))
        #expect(LarderColor.status(.info) == LarderColor.color(.statusInfo))
    }

    @Test func namespacesResolveTheirTokens() {
        #expect(LarderColor.surface.canvas == LarderColor.color(.surfaceCanvas))
        #expect(LarderColor.ink.primary == LarderColor.color(.inkPrimary))
        #expect(LarderColor.accent.brand == LarderColor.color(.accentBrand))
        #expect(LarderColor.line.strong == LarderColor.color(.lineStrong))
    }
}

@MainActor
@Suite("Components")
struct ComponentRuleTests {
    @Test func fillFractionPerLevel() {
        #expect(ShelfBand.fillFraction(for: .light) == 0.3)
        #expect(ShelfBand.fillFraction(for: .comfortable) == 0.65)
        #expect(ShelfBand.fillFraction(for: .heavy) == 1)
    }

    @Test func fillGrowsWithLevel() {
        let fractions = ShelfBand.Level.allCases.map { ShelfBand.fillFraction(for: $0) }
        #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func levelsSitAroundTheComfortableBracket() {
        let range = ShelfBand.comfortableRange
        #expect(range == 0.4...0.8)
        #expect(ShelfBand.fillFraction(for: .light) < range.lowerBound)
        #expect(range.contains(ShelfBand.fillFraction(for: .comfortable)))
        #expect(ShelfBand.fillFraction(for: .heavy) > range.upperBound)
    }

    @Test func shelfBandIsAtLeastSixPointsTall() {
        #expect(ShelfBand.barHeight >= 6)
    }

    @Test func shelfLevelWordsAreWordsNotNumbers() {
        let words = ShelfBand.Level.allCases.map(\.word)
        #expect(words == ["Light", "Comfortable", "Heavy"])
    }

    @Test func buttonsMeetTheMinimumHitTarget() {
        #expect(LarderButtonStyle.minimumHitTarget == 44)
    }

    @Test func primaryPressDarkensByEightPercent() {
        #expect(LarderButtonStyle.pressedDarkening == 0.08)
    }
}
