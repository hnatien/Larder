import SwiftUI
import Testing
@testable import LarderDesign

/// Text must scale with Dynamic Type: no fixed sizes, no shrinking and no caps, so the audit sees it grow.
@Suite("Dynamic Type")
struct DynamicTypeTests {
    private static let scanned: [URL] = {
        let sources = DesignSources.repoRoot.appending(path: "Sources")
        let roots = [DesignSources.module] + ((try? FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("Feature") }
        return roots.flatMap { DesignSources.files(withExtension: "swift", under: $0) }
    }()

    private func offenders(_ matches: (String) -> Bool) throws -> [String] {
        try Self.scanned.compactMap { url in
            matches(try DesignSources.text(url)) ? url.lastPathComponent : nil
        }
    }

    @Test func featureAndDesignSourcesAreFound() {
        #expect(Self.scanned.count > 60)
        for feature in ["Shelves", "Ledger", "Recipes", "Grocery", "Account"] {
            #expect(Self.scanned.contains { $0.path.contains("Sources/Feature\(feature)/") }, "no sources under Feature\(feature)")
        }
    }

    @Test func noFixedSizeFonts() throws {
        let fixed = try Regex(#"\.font\(\s*\.system\(\s*size\s*:"#)
        let found = try offenders { $0.contains(fixed) }
        #expect(found.isEmpty, "fixed-size fonts in \(found)")
    }

    @Test func noMinimumScaleFactor() throws {
        let found = try offenders { $0.contains(".minimumScaleFactor(") }
        #expect(found.isEmpty, "minimumScaleFactor in \(found)")
    }

    @Test func noDynamicTypeCap() throws {
        let found = try offenders { $0.contains(".dynamicTypeSize(") || $0.contains("larderDisplayScale") }
        #expect(found.isEmpty, "Dynamic Type capped in \(found); display text must grow to AX5, which the audit requires")
    }
}
