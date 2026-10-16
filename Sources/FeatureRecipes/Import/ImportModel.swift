import Foundation
import LarderCore
import Observation

/// The state behind the import sheet: address in, preview out, then save.
@Observable
@MainActor
public final class ImportModel: Identifiable {
    /// Where the sheet is in the flow.
    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case preview(ImportResult)
        case failed(ImportError)
        case saving
        case saved
    }

    public var id: ObjectIdentifier { ObjectIdentifier(self) }
    /// The address as typed or pasted.
    public var addressText = ""
    public private(set) var phase = Phase.idle

    private let importer: RecipeImporter
    private let saveResult: (ImportResult) async throws -> Void
    private let fetch: @Sendable (URL) async throws -> (Data, String)

    init(
        importer: RecipeImporter,
        fetch: @escaping @Sendable (URL) async throws -> (Data, String) = RecipeImporter.liveFetch,
        save: @escaping (ImportResult) async throws -> Void
    ) {
        self.importer = importer
        self.fetch = fetch
        self.saveResult = save
    }

    /// The previewed recipe, if there is one.
    public var preview: ImportResult? {
        if case .preview(let result) = phase { result } else { nil }
    }

    /// Fetches the page at `addressText` and shows what was found.
    public func fetchPreview() async {
        guard let url = Self.url(from: addressText) else {
            phase = .failed(.invalidURL)
            return
        }
        phase = .loading
        do {
            let result = try await importer.import(from: url, fetch: fetch)
            guard !Task.isCancelled else { return }
            phase = .preview(result)
        } catch let error as ImportError {
            phase = .failed(error)
        } catch {
            phase = .idle
        }
    }

    /// Changes the servings of the previewed recipe before saving.
    public func setServings(_ servings: Int) {
        guard case .preview(var result) = phase, servings > 0 else { return }
        result.recipe.servings = servings
        phase = .preview(result)
    }

    /// Saves the previewed recipe; returns whether it was saved.
    @discardableResult
    public func save() async -> Bool {
        guard case .preview(let result) = phase else { return false }
        phase = .saving
        do {
            try await saveResult(result)
        } catch {
            phase = .failed(.saveFailed)
            return false
        }
        phase = .saved
        return true
    }

    /// Returns to the address field, keeping what was typed.
    public func reset() {
        phase = .idle
    }

    private static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed)
    }
}
