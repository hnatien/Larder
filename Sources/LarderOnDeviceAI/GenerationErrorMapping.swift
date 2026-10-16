import FoundationModels
import LarderCore

/// The on-device generation failures Larder tells apart.
nonisolated enum GenerationFailure: Equatable, Sendable {
    case guardrailViolation
    case exceededContextWindow
    case unsupportedLanguage
    case other
}

/// An error the on-device model throws, reduced to the failure Larder acts on; a seam so tests need no model.
nonisolated protocol GenerationErrorKind: Error {
    /// The failure this error reports.
    var generationFailure: GenerationFailure { get }
}

extension LanguageModelSession.GenerationError: GenerationErrorKind {
    nonisolated var generationFailure: GenerationFailure {
        switch self {
        case .guardrailViolation: .guardrailViolation
        case .exceededContextWindowSize: .exceededContextWindow
        case .unsupportedLanguageOrLocale: .unsupportedLanguage
        case .assetsUnavailable, .unsupportedGuide, .decodingFailure, .rateLimited, .concurrentRequests, .refusal: .other
        @unknown default: .other
        }
    }
}

@available(iOS 27.0, macOS 27.0, *)
extension LanguageModelError: GenerationErrorKind {
    nonisolated var generationFailure: GenerationFailure {
        switch self {
        case .guardrailViolation: .guardrailViolation
        case .contextSizeExceeded: .exceededContextWindow
        case .unsupportedLanguageOrLocale: .unsupportedLanguage
        default: .other
        }
    }
}

/// Maps errors from an on-device request to the errors the rest of the app handles.
nonisolated enum GenerationErrorMapper {
    /// `LarderError` and cancellation pass through; model failures map to a `LarderError`; anything else means the assistant is unavailable.
    static func map(_ error: any Error) -> any Error {
        if error is LarderError || error is CancellationError { return error }
        guard let kind = error as? any GenerationErrorKind else { return LarderError.assistantUnavailable }
        switch kind.generationFailure {
        case .guardrailViolation: return LarderError.declined(category: "guardrail")
        case .exceededContextWindow: return LarderError.invalidResponse
        case .unsupportedLanguage, .other: return LarderError.assistantUnavailable
        }
    }
}
