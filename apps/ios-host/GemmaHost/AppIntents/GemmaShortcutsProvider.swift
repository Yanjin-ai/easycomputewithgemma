import AppIntents

struct GemmaShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GemmaSubmitTaskIntent(),
            phrases: [
                "Ask \(.applicationName) to \(\.$taskText)",
                "Use \(.applicationName) to \(\.$taskText)",
                "\(.applicationName) \(\.$taskText)",
            ],
            shortTitle: "Ask Gemma",
            systemImageName: "brain.head.profile"
        )
    }
}
