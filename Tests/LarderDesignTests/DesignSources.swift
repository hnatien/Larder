import Foundation

/// Locates the module's source tree from the test file's own path.
enum DesignSources {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    static let module = repoRoot.appending(path: "Sources/LarderDesign")
    static let resources = module.appending(path: "Resources")
    static let colors = resources.appending(path: "Colors.xcassets")
    static let catalogue = resources.appending(path: "Localizable.xcstrings")

    static func files(withExtension ext: String, under root: URL = module) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == ext }.sorted { $0.path < $1.path }
    }

    static func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
