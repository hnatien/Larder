import AppIntents
import Foundation

/// Why a Larder intent could not answer.
nonisolated enum LarderIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// The app's store is not available in this process.
    case storeUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .storeUnavailable: "Larder couldn't read your plan. Open Larder and try again."
        }
    }
}

/// Says tonight's planned dinner and how long it takes, without opening the app.
nonisolated struct WhatsForDinnerIntent: AppIntent {
    static let title: LocalizedStringResource = "What's for dinner"
    static let description = IntentDescription("Tells you tonight's planned dinner and how long it takes.")
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let dependencies = AppDependencies.shared else { throw LarderIntentError.storeUnavailable }
        guard let dinner = try await dependencies.dinners.tonight(at: Date()) else {
            return .result(dialog: "Nothing planned yet. Open Larder for three ideas.")
        }
        return .result(dialog: "Tonight it's \(dinner.title), \(dinner.minutes) minutes.")
    }
}
