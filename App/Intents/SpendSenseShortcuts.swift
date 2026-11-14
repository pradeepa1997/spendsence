import AppIntents

/// Makes the actions available in Shortcuts and Siri as soon as the app is installed.
struct SpendSenseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogTransactionFromSMSIntent(),
            phrases: ["Log SMS in \(.applicationName)"],
            shortTitle: "Log SMS",
            systemImageName: "message.badge"
        )
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add expense in \(.applicationName)",
                "Add a cash expense in \(.applicationName)",
            ],
            shortTitle: "Add Expense",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: GetMonthlySpendIntent(),
            phrases: [
                "How much did I spend in \(.applicationName)",
                "Monthly spending in \(.applicationName)",
            ],
            shortTitle: "Monthly Spending",
            systemImageName: "chart.pie"
        )
    }
}
