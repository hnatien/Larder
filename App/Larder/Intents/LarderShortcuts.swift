import AppIntents

/// The phrases Siri and Shortcuts offer without setup.
nonisolated struct LarderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsForDinnerIntent(),
            phrases: ["What's for dinner in \(.applicationName)"],
            shortTitle: "What's for dinner",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: OpenTonightIntent(),
            phrases: ["Open \(.applicationName) tonight"],
            shortTitle: "Open Tonight",
            systemImageName: "sun.horizon"
        )
    }
}
