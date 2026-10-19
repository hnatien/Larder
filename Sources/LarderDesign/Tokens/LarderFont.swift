import CoreText
import SwiftUI

/// Larder's three faces: Fraunces for display, SF Pro for body, Commit Mono for stamps.
public enum LarderFont {
    /// A bundled display instance and how big and heavy its system fallback is.
    struct DisplaySpec: Equatable {
        let postScriptName: String
        let size: CGFloat
        let weight: Font.Weight
    }

    /// Commit Mono 400 Regular, shipped unmodified as `CommitMono-400-Regular.otf`.
    static let monoPostScriptName = "CommitMono-Regular"
    /// Tracking for stamps, in em.
    static let stampTracking: CGFloat = 0.04

    /// True once at least one bundled font file has been registered.
    public private(set) static var hasBundledFonts = false
    private static var didAttemptRegistration = false

    /// Registers every `.ttf` and `.otf` in the module's `Fonts` resources; safe to call more than once.
    @discardableResult
    public static func registerBundledFonts() -> Bool {
        guard !didAttemptRegistration else { return hasBundledFonts }
        didAttemptRegistration = true
        guard let root = Bundle.module.resourceURL,
              let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return false }
        var registered = 0
        for case let url as URL in files where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) { registered += 1 }
        }
        hasBundledFonts = registered > 0
        return hasBundledFonts
    }

    /// The licence files shipped next to the fonts, unchanged, Fraunces first.
    static let licenceFileNames = ["Fraunces-OFL", "CommitMono-OFL"]

    /// The full text of each bundled font's licence, for the acknowledgements screen; a file missing from the bundle is left out.
    public static var licenceTexts: [String] {
        licenceFileNames.compactMap { name in
            let url = Bundle.module.url(forResource: name, withExtension: "txt")
                ?? Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fonts")
            return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
    }

    /// Fraunces static instance for display text, scaling with Dynamic Type; falls back to the system serif.
    public static func display(_ style: Font.TextStyle) -> Font {
        let spec = displaySpec(for: style)
        guard hasBundledFonts else { return .system(style, design: .serif, weight: spec.weight) }
        return .custom(spec.postScriptName, size: spec.size, relativeTo: style)
    }

    /// SF Pro text style for body and UI.
    public static func body(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .default, weight: weight)
    }

    /// Commit Mono for stamps and quantities; falls back to the system monospaced face.
    public static func mono(_ style: Font.TextStyle) -> Font {
        guard hasBundledFonts else { return .system(style, design: .monospaced) }
        return .custom(monoPostScriptName, size: monoSize(for: style), relativeTo: style)
    }

    static func displaySpec(for style: Font.TextStyle) -> DisplaySpec {
        switch style {
        case .largeTitle: DisplaySpec(postScriptName: "Fraunces144pt-SoftMedium", size: 34, weight: .medium)
        case .title: DisplaySpec(postScriptName: "Fraunces144pt-SoftBold", size: 28, weight: .bold)
        default: DisplaySpec(postScriptName: "Fraunces72pt-SoftSemiBold", size: 22, weight: .semibold)
        }
    }

    static func monoSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body, .callout: 17
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}

private struct StampStyle: ViewModifier {
    @ScaledMetric(relativeTo: .caption) private var size = LarderFont.monoSize(for: .caption)

    func body(content: Content) -> some View {
        content
            .font(LarderFont.mono(.caption))
            .textCase(.uppercase)
            .tracking(LarderFont.stampTracking * size)
    }
}

public extension View {
    /// Mono, uppercase, 0.04 em tracking.
    func stamp() -> some View {
        modifier(StampStyle())
    }
}
