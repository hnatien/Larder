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
        case readingPhoto
        case preview(ImportResult)
        case failed(ImportError)
        case saving
        case saved
    }

    public var id: ObjectIdentifier { ObjectIdentifier(self) }
    /// The address as typed or pasted.
    public var addressText = ""
    /// A recipe written out by hand: its title, one ingredient per line, one step per line, and minutes.
    public var writtenTitle = ""
    public var writtenIngredients = ""
    public var writtenSteps = ""
    public var writtenMinutes: Int?
    public private(set) var phase = Phase.idle

    private let importer: RecipeImporter
    private let saveResult: (ImportResult) async throws -> Void
    private let fetch: @Sendable (URL) async throws -> (Data, String)
    private let allowAI: (() async -> Bool)?
    /// The last photo read, so it can be read again once AI help is allowed.
    private var lastPhoto: Data?

    init(
        importer: RecipeImporter,
        fetch: @escaping @Sendable (URL) async throws -> (Data, String) = RecipeImporter.liveFetch,
        allowAI: (() async -> Bool)? = nil,
        save: @escaping (ImportResult) async throws -> Void
    ) {
        self.importer = importer
        self.fetch = fetch
        self.allowAI = allowAI
        self.saveResult = save
    }

    /// Whether the last failure was AI help being off, and it can be allowed from here.
    public var canAllowAI: Bool {
        guard allowAI != nil, case .failed(let error) = phase else { return false }
        switch error {
        case .assistantFailed(.consentRequired), .photoAssistantFailed(.consentRequired): return true
        default: return false
        }
    }

    /// Turns on AI help after the user allowed it, then reads the page or photo that needed it again.
    public func allowAIAndRetry() async {
        guard let allowAI, case .failed(let error) = phase else { return }
        guard await allowAI() else { return }
        switch error {
        case .photoAssistantFailed:
            if let lastPhoto { await readPhoto(lastPhoto) }
        default:
            await fetchPreview()
        }
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

    /// Reads the recipe in a photo from the camera or the photo library and shows what was found.
    public func readPhoto(_ data: Data) async {
        lastPhoto = data
        phase = .readingPhoto
        do {
            let result = try await importer.import(photo: data)
            guard !Task.isCancelled else { return }
            phase = .preview(result)
        } catch let error as ImportError {
            phase = .failed(error)
        } catch {
            phase = .idle
        }
    }

    /// Previews the recipe written out by hand.
    public func readWritten() async {
        do {
            phase = .preview(try await importer.import(
                title: writtenTitle, ingredients: writtenIngredients, steps: writtenSteps, minutes: writtenMinutes
            ))
        } catch let error as ImportError {
            phase = .failed(error)
        } catch {
            phase = .idle
        }
    }

    /// Whether the written recipe has enough to preview: a title and an ingredient or a step.
    public var canReadWritten: Bool {
        !writtenTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(RecipeImporter.lines(writtenIngredients).isEmpty && RecipeImporter.lines(writtenSteps).isEmpty)
    }

    /// Shows that a chosen photo could not be loaded from the library.
    public func photoUnavailable() {
        phase = .failed(.unreadablePhoto)
    }

    /// Whether a page or photo is being read or the recipe saved, so new input waits.
    public var isBusy: Bool {
        switch phase {
        case .loading, .readingPhoto, .saving: true
        case .idle, .preview, .failed, .saved: false
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
