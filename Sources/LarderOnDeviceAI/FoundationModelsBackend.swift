import Foundation
import FoundationModels
import LarderAssistant
import LarderCore

/// The on-device assistant: parses pantry and recipe text with Apple's Foundation Models.
///
/// Explaining plans and adjusting constraints go to the proxy; those calls throw `LarderError.assistantUnavailable`.
public actor FoundationModelsBackend: AssistantBackend, OnDeviceAvailability {
    private let model: SystemLanguageModel
    private let modelIsAvailable: @Sendable () -> Bool
    private let textExtractor = DocumentTextExtractor()
    private var preparedPantrySession: LanguageModelSession?

    /// Creates a backend over `model`.
    public init(model: SystemLanguageModel = .default) {
        self.init(model: model, modelIsAvailable: { model.availability == .available })
    }

    init(model: SystemLanguageModel, modelIsAvailable: @escaping @Sendable () -> Bool) {
        self.model = model
        self.modelIsAvailable = modelIsAvailable
    }

    public nonisolated var isAvailable: Bool { modelIsAvailable() }

    public nonisolated var supportedRoutes: Set<AssistantRoute> { [.parsePantry, .parseRecipe] }

    /// Loads the model with the pantry instructions ahead of the next pantry request; call when the app is idle.
    public func prepare() {
        guard isAvailable, preparedPantrySession == nil else { return }
        let session = LanguageModelSession(model: model, instructions: Instructions(OnDevicePrompts.Pantry.instructions))
        session.prewarm()
        preparedPantrySession = session
    }

    public func explain(plan: PlanExplainRequest) async throws -> PlanExplanation {
        throw LarderError.assistantUnavailable
    }

    public func adjust(request: AdjustRequest) async throws -> ConstraintEdit {
        throw LarderError.assistantUnavailable
    }

    public func parsePantry(text: String) async throws -> [ParsedPantryLine] {
        guard isAvailable else { throw LarderError.assistantUnavailable }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let session = preparedPantrySession ?? LanguageModelSession(
            model: model,
            instructions: Instructions(OnDevicePrompts.Pantry.instructions)
        )
        preparedPantrySession = nil
        do {
            let fitted = try await fit(
                trimmed,
                instructions: OnDevicePrompts.Pantry.instructions,
                schema: PantryLines.generationSchema,
                allowsTruncation: true
            )
            let response = try await session.respond(to: Prompt(fitted), generating: PantryLines.self)
            return response.content.lines.map(PantryLineMapper.map).filter { !$0.name.isEmpty }
        } catch {
            throw GenerationErrorMapper.map(error)
        }
    }

    public func parseRecipe(text: String, imageData: Data?) async throws -> ParsedRecipe {
        guard isAvailable else { throw LarderError.assistantUnavailable }
        var parts = [text.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let imageData {
            do {
                parts.append(try await textExtractor.lines(in: imageData).joined(separator: "\n"))
            } catch is ImageScanError {
                throw LarderError.invalidResponse
            }
        }
        let pageText = parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !pageText.isEmpty else { throw LarderError.invalidResponse }
        do {
            let fitted = try await fit(
                pageText,
                instructions: OnDevicePrompts.Recipe.instructions,
                schema: RecipeDraft.generationSchema,
                allowsTruncation: false
            )
            let session = LanguageModelSession(model: model, instructions: Instructions(OnDevicePrompts.Recipe.instructions))
            let response = try await session.respond(to: Prompt(fitted), generating: RecipeDraft.self)
            let recipe = RecipeDraftMapper.map(response.content)
            guard !recipe.title.isEmpty else { throw LarderError.invalidResponse }
            return recipe
        } catch {
            throw GenerationErrorMapper.map(error)
        }
    }

    private func fit(_ text: String, instructions: String, schema: GenerationSchema, allowsTruncation: Bool) async throws -> String {
        let textTokens: Int
        let overheadTokens: Int
        if #available(iOS 26.4, macOS 26.4, *) {
            textTokens = try await model.tokenCount(for: Prompt(text))
            overheadTokens = try await model.tokenCount(for: Instructions(instructions)) + model.tokenCount(for: schema)
        } else {
            textTokens = ContextGuard.estimatedTokens(for: text)
            let schemaJSON = String(decoding: try JSONEncoder().encode(schema), as: UTF8.self)
            overheadTokens = ContextGuard.estimatedTokens(for: instructions) + ContextGuard.estimatedTokens(for: schemaJSON)
        }
        let fitted = ContextGuard.fit(
            text,
            textTokens: textTokens,
            overheadTokens: overheadTokens,
            contextSize: model.contextSize,
            allowsTruncation: allowsTruncation
        )
        guard let fitted else { throw LarderError.invalidResponse }
        return fitted
    }
}
