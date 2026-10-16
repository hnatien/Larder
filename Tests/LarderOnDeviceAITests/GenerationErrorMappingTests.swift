import FoundationModels
import Testing
import LarderCore
@testable import LarderOnDeviceAI

/// A model error double for the `GenerationErrorKind` seam.
struct FakeGenerationError: GenerationErrorKind {
    let generationFailure: GenerationFailure
}

struct UnrelatedError: Error {}

struct GenerationErrorMappingTests {
    @Test(arguments: [
        (GenerationFailure.guardrailViolation, LarderError.declined(category: "guardrail")),
        (.exceededContextWindow, .invalidResponse),
        (.unsupportedLanguage, .assistantUnavailable),
        (.other, .assistantUnavailable),
    ])
    func eachFailureMapsToALarderError(failure: GenerationFailure, expected: LarderError) {
        #expect(GenerationErrorMapper.map(FakeGenerationError(generationFailure: failure)) as? LarderError == expected)
    }

    @Test func everyGenerationErrorCaseReportsItsFailure() {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        let cases: [(LanguageModelSession.GenerationError, GenerationFailure)] = [
            (.guardrailViolation(context), .guardrailViolation),
            (.exceededContextWindowSize(context), .exceededContextWindow),
            (.unsupportedLanguageOrLocale(context), .unsupportedLanguage),
            (.assetsUnavailable(context), .other),
            (.unsupportedGuide(context), .other),
            (.decodingFailure(context), .other),
            (.rateLimited(context), .other),
            (.concurrentRequests(context), .other),
            (.refusal(.init(transcriptEntries: []), context), .other),
        ]
        for (error, failure) in cases {
            #expect(error.generationFailure == failure)
        }
    }

    @Test func realGenerationErrorsMapThroughTheSeam() {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        #expect(GenerationErrorMapper.map(LanguageModelSession.GenerationError.guardrailViolation(context)) as? LarderError == .declined(category: "guardrail"))
        #expect(GenerationErrorMapper.map(LanguageModelSession.GenerationError.exceededContextWindowSize(context)) as? LarderError == .invalidResponse)
        #expect(GenerationErrorMapper.map(LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(context)) as? LarderError == .assistantUnavailable)
    }

    @Test func larderErrorsAndCancellationPassThrough() {
        #expect(GenerationErrorMapper.map(LarderError.invalidResponse) as? LarderError == .invalidResponse)
        #expect(GenerationErrorMapper.map(LarderError.declined(category: nil)) as? LarderError == .declined(category: nil))
        #expect(GenerationErrorMapper.map(CancellationError()) is CancellationError)
    }

    @Test func unrelatedErrorsMeanTheAssistantIsUnavailable() {
        #expect(GenerationErrorMapper.map(UnrelatedError()) as? LarderError == .assistantUnavailable)
    }
}
