import Foundation
import Testing

/// Greps the module's own sources and string catalogue for the looks Larder refuses.
@Suite("Banned tokens")
struct BannedTokenTests {
    private static let scanned: [URL] = DesignSources.files(withExtension: "swift") + [DesignSources.catalogue]

    private func offenders(_ matches: (String) -> Bool) throws -> [String] {
        try Self.scanned.compactMap { url in
            matches(try DesignSources.text(url)) ? url.lastPathComponent : nil
        }
    }

    @Test func sourcesAreFound() {
        #expect(Self.scanned.count > 20)
    }

    @Test func noGradients() throws {
        let found = try offenders { $0.contains("Gradient") }
        #expect(found.isEmpty, "gradients in \(found)")
    }

    @Test func noShadows() throws {
        let found = try offenders { $0.contains(".shadow(") }
        #expect(found.isEmpty, "shadows in \(found)")
    }

    @Test func noEmDashes() throws {
        let found = try offenders { $0.contains("\u{2014}") }
        #expect(found.isEmpty, "em dashes in \(found)")
    }

    @Test func noEmoji() throws {
        let found = try offenders { text in
            text.unicodeScalars.contains { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0xFF) }
        }
        #expect(found.isEmpty, "emoji in \(found)")
    }

    @Test func noInterFont() throws {
        let word = try Regex(#"\bInter\b"#)
        let found = try offenders { $0.contains(word) }
        #expect(found.isEmpty, "Inter in \(found)")
    }

    @Test func noPurpleOrIndigo() throws {
        let found = try offenders { text in
            let lowered = text.lowercased()
            return lowered.contains("purple") || lowered.contains("indigo")
        }
        #expect(found.isEmpty, "purple or indigo in \(found)")
    }

    @Test func everyComponentFileHasAPreview() throws {
        let components = DesignSources.files(withExtension: "swift", under: DesignSources.module.appending(path: "Components"))
        #expect(components.count == 12)
        for file in components {
            #expect(try DesignSources.text(file).contains("#Preview"), "\(file.lastPathComponent) lacks a #Preview")
        }
    }
}
