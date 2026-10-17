import AppIntents

/// Opens Larder on the Tonight tab.
nonisolated struct OpenTonightIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Tonight"
    static let description = IntentDescription("Opens Larder on three dinner ideas from your pantry.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let dependencies = AppDependencies.shared else { throw LarderIntentError.storeUnavailable }
        dependencies.state.selectedTab = .tonight
        return .result()
    }
}
