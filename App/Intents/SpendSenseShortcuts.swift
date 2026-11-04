import AppIntents

/// Makes "Log Transaction from SMS" available in Shortcuts as soon as the app is installed.
struct SpendSenseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogTransactionFromSMSIntent(),
            phrases: ["Log SMS in \(.applicationName)"],
            shortTitle: "Log SMS",
            systemImageName: "message.badge"
        )
    }
}
