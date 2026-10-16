import CoreText
import SwiftUI
import Testing
@testable import LarderDesign

@MainActor
@Suite("Font registration")
struct FontRegistrationTests {
    private static let allStyles: [Font.TextStyle] = [
        .largeTitle, .title, .title2, .title3, .headline, .body, .callout, .subheadline, .footnote, .caption, .caption2,
    ]

    /// Every PostScript name `LarderFont` selects a face by.
    private static let requestedNames = Set(allStyles.map { LarderFont.displaySpec(for: $0).postScriptName })
        .union([LarderFont.monoPostScriptName])

    @Test func bundledFontsRegister() {
        #expect(LarderFont.registerBundledFonts())
        #expect(LarderFont.hasBundledFonts)
    }

    @Test func everyRequestedNameResolvesToThatExactFont() {
        #expect(LarderFont.registerBundledFonts())
        #expect(Self.requestedNames.count == 4)
        for name in Self.requestedNames {
            // CoreText substitutes a fallback face for an unknown name, so the name it hands back is the real check.
            let font = CTFontCreateWithName(name as CFString, 17, nil)
            #expect(CTFontCopyPostScriptName(font) as String == name)
        }
    }

    @Test func everyRequestedNameShipsInTheResources() throws {
        let files = DesignSources.files(withExtension: "ttf", under: DesignSources.resources)
            + DesignSources.files(withExtension: "otf", under: DesignSources.resources)
        let shipped = try Set(files.flatMap { url in
            let descriptors = try #require(CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])
            return descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
        })
        #expect(Self.requestedNames.isSubset(of: shipped), "missing: \(Self.requestedNames.subtracting(shipped))")
    }
}
