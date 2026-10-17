import Foundation
import LarderCore

/// Why an import failed; every case has copy the user can act on.
public nonisolated enum ImportError: Error, Hashable, Sendable {
    /// The text is not an http or https address.
    case invalidURL
    /// The page could not be downloaded.
    case fetchFailed
    /// The address returned something other than a web page, or a page that is too large.
    case notAWebPage
    /// The page has no schema.org recipe and the assistant is not available to read it.
    case noStructuredRecipe
    /// The assistant was asked to read the page and could not.
    case assistantFailed(LarderError)
    /// The recipe was read but could not be saved.
    case saveFailed
    /// Reading a recipe from a photo is a Larder Plus feature.
    case photoNeedsPlus
    /// The photo could not be opened, or no recipe could be read from it.
    case unreadablePhoto
    /// The assistant was asked to read the photo and could not.
    case photoAssistantFailed(LarderError)
}

/// A recipe ready to preview and save.
public nonisolated struct ImportResult: Hashable, Sendable {
    /// Where the recipe data came from.
    public enum Source: Hashable, Sendable {
        case structuredData
        case assistant
        /// Read from a photo of a recipe page or card.
        case photo
    }

    public var recipe: Recipe
    public var ingredients: [Ingredient]
    public var source: Source
    /// The page's photo as a downsampled JPEG, written to the photo store on save; `nil` when the page has none.
    public var photo: Data?

    /// Creates an import result.
    public init(recipe: Recipe, ingredients: [Ingredient], source: Source, photo: Data? = nil) {
        self.recipe = recipe
        self.ingredients = ingredients
        self.source = source
        self.photo = photo
    }
}

/// Fetches a recipe page on the device and turns it into a recipe, with the photo its structured data names.
nonisolated struct RecipeImporter: Sendable {
    /// Servings used when the page gives no yield.
    static let defaultServings = 4
    /// The most page text sent to the assistant, in characters.
    static let assistantTextLimit = 20_000
    /// A first-word match is a weak signal, so it reports well below certainty.
    static let firstWordMatchConfidence = 0.5
    private static let maximumPageBytes = 5_000_000
    private static let maximumPhotoBytes = 10_000_000
    /// The largest camera or library photo read for a recipe, before it is downsampled.
    static let maximumRecipePhotoBytes = 40_000_000
    /// The longest side of a recipe photo sent to be read: sharp enough for small print, well inside the proxy's image limit.
    static let readingPixelSize = 2048

    let foods: any FoodRepository
    let profile: any ProfileRepository
    let assistant: any AssistantBackend
    let isPlus: @Sendable () async -> Bool

    /// Downloads a page or its photo with an ephemeral session; returns the body and its Content-Type header.
    static let liveFetch: @Sendable (URL) async throws -> (Data, String) = { url in
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if components?.scheme == "http" { components?.scheme = "https" }
        guard let secure = components?.url else { throw ImportError.invalidURL }
        var request = URLRequest(url: secure, timeoutInterval: 20)
        request.setValue("text/html,application/xhtml+xml,image/*;q=0.9", forHTTPHeaderField: "Accept")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ImportError.fetchFailed
        }
        return (data, http.value(forHTTPHeaderField: "Content-Type") ?? "")
    }

    /// Reads the recipe at `url`: schema.org data first, then, for consented Plus users, the assistant. The photo
    /// named by schema.org data is fetched too; one that cannot be fetched or read leaves the recipe without a photo.
    func `import`(
        from url: URL,
        fetch: @Sendable (URL) async throws -> (Data, String)
    ) async throws -> ImportResult {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            throw ImportError.invalidURL
        }
        let html = try await page(at: url, fetch: fetch)

        let structured: StructuredRecipe
        let source: ImportResult.Source
        do {
            structured = try JSONLDRecipeParser.parseStructured(html: html)
            source = .structuredData
        } catch {
            structured = StructuredRecipe(recipe: try await assistantRecipe(from: html), tags: RecipeTags())
            source = .assistant
        }
        var imported = await result(from: structured, url: url, source: source)
        if let address = structured.imageAddress {
            imported.photo = try await photo(at: address, on: url, fetch: fetch)
        }
        return imported
    }

    /// Reads the recipe in a photo of a page or card, for Plus users. The assistant reads it on this device first
    /// (Vision text and Foundation Models) and, when AI help is allowed, falls back to the proxy's image route.
    /// The photo is not kept with the recipe: it shows a page, not the dish.
    func `import`(photo data: Data) async throws -> ImportResult {
        guard await isPlus() else { throw ImportError.photoNeedsPlus }
        guard data.count <= Self.maximumRecipePhotoBytes,
              let jpeg = PhotoDownsampler.jpeg(from: data, maximumPixelSize: Self.readingPixelSize)
        else { throw ImportError.unreadablePhoto }
        let consented = (try? await profile.profile())?.consents.aiProcessing == true
        let parsed: ParsedRecipe
        do {
            parsed = try await assistant.parseRecipe(text: "", imageData: jpeg)
        } catch LarderError.assistantUnavailable where !consented {
            // Nothing on this device could read it and the proxy was not allowed to try.
            throw ImportError.photoAssistantFailed(.consentRequired)
        } catch LarderError.invalidResponse {
            throw ImportError.unreadablePhoto
        } catch let error as LarderError {
            throw ImportError.photoAssistantFailed(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ImportError.photoAssistantFailed(.assistantUnavailable)
        }
        guard !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty, !parsed.ingredients.isEmpty || !parsed.steps.isEmpty else {
            throw ImportError.unreadablePhoto
        }
        return await result(from: StructuredRecipe(recipe: parsed, tags: RecipeTags()), url: nil, source: .photo)
    }

    /// The photo at `address`, resolved against the page, as a stored JPEG; `nil` for anything that is not a readable
    /// http or https image within the size limit. Only cancellation is thrown.
    private func photo(
        at address: String,
        on page: URL,
        fetch: @Sendable (URL) async throws -> (Data, String)
    ) async throws -> Data? {
        guard let url = URL(string: address, relativeTo: page)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil
        else { return nil }
        let data: Data
        let contentType: String
        do {
            (data, contentType) = try await fetch(url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
        guard data.count <= Self.maximumPhotoBytes, contentType.lowercased().hasPrefix("image/") else { return nil }
        try Task.checkCancellation()
        return PhotoDownsampler.jpeg(from: data)
    }

    private func page(at url: URL, fetch: @Sendable (URL) async throws -> (Data, String)) async throws -> String {
        let data: Data
        let contentType: String
        do {
            (data, contentType) = try await fetch(url)
        } catch let error as ImportError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ImportError.fetchFailed
        }
        let type = contentType.lowercased()
        guard data.count <= Self.maximumPageBytes, type.isEmpty || type.contains("html") else {
            throw ImportError.notAWebPage
        }
        return Self.decode(data, contentType: type)
    }

    private static func decode(_ data: Data, contentType: String) -> String {
        let charset = contentType.range(of: "charset=").map { contentType[$0.upperBound...].prefix { $0 != ";" && $0 != " " } }
        let encoding: String.Encoding = switch charset.map(String.init)?.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) {
        case "iso-8859-1", "latin1": .isoLatin1
        case "windows-1252": .windowsCP1252
        default: .utf8
        }
        return String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
    }

    private func assistantRecipe(from html: String) async throws -> ParsedRecipe {
        let consented = (try? await profile.profile())?.consents.aiProcessing == true
        guard await isPlus(), consented else { throw ImportError.noStructuredRecipe }
        let text = HTMLText.visibleText(from: html, limit: Self.assistantTextLimit)
        guard !text.isEmpty else { throw ImportError.noStructuredRecipe }
        let parsed: ParsedRecipe
        do {
            parsed = try await assistant.parseRecipe(text: text, imageData: nil)
        } catch let error as LarderError {
            throw ImportError.assistantFailed(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ImportError.assistantFailed(.assistantUnavailable)
        }
        guard !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty, !parsed.ingredients.isEmpty || !parsed.steps.isEmpty else {
            throw ImportError.noStructuredRecipe
        }
        return parsed
    }

    private func result(from structured: StructuredRecipe, url: URL?, source: ImportResult.Source) async -> ImportResult {
        let parsed = structured.recipe
        let recipe = Recipe(
            title: parsed.title,
            origin: .userImport,
            sourceURL: url,
            license: nil,
            servings: parsed.servings.flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultServings,
            prepMinutes: parsed.prepMinutes ?? 0,
            cookMinutes: parsed.cookMinutes ?? 0,
            steps: parsed.steps.map { RecipeStep(text: $0.text, timerSeconds: $0.timerSeconds ?? TimerDetector.seconds(in: $0.text)) },
            tags: structured.tags
        )
        var ingredients: [Ingredient] = []
        for line in parsed.ingredients {
            let match = await foodMatch(for: line.name)
            ingredients.append(Ingredient(
                recipeID: recipe.id,
                rawText: line.rawText,
                quantity: line.quantity ?? 0,
                unit: line.unit ?? .piece,
                foodID: match?.id,
                matchConfidence: match == nil ? 0 : Self.firstWordMatchConfidence,
                isOptional: line.rawText.range(of: "optional", options: .caseInsensitive) != nil
            ))
        }
        return ImportResult(recipe: recipe, ingredients: ingredients, source: source)
    }

    private func foodMatch(for name: String) async -> Food? {
        guard let word = Self.firstWord(of: name).map(WordForms.singular),
              let hit = try? await foods.search(text: word, limit: 1).first,
              Self.firstWord(of: hit.name).map(WordForms.singular) == word
        else { return nil }
        return hit
    }

    private static func firstWord(of text: String) -> String? {
        WordForms.words(text).first
    }
}
