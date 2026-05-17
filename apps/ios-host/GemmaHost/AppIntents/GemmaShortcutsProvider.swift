import AppIntents

struct GemmaShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GemmaSubmitTaskIntent(),
            phrases: [
                // String parameters cannot be interpolated in AppShortcut phrases
                // (only AppEntity / AppEnum are allowed). Use static phrases instead;
                // Siri will prompt the user for taskText after the phrase is matched.
                "Ask \(.applicationName)",
                "Use \(.applicationName)",
                "Run a task on \(.applicationName)",
            ],
            shortTitle: "Ask Gemma",
            systemImageName: "brain.head.profile"
        )
    }
}
