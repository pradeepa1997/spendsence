import AppIntents
import Foundation
import SpendCore

/// "Add expense in SpendSense": quick cash / manual entry from Siri, Shortcuts or the Action button.
struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription("Adds a cash or manual expense to SpendSense.")
    static let openAppWhenRun = false

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Description")
    var merchant: String?

    @Parameter(title: "Category", description: "A category name such as Dining or Transport.")
    var category: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) for \(\.$merchant) in \(\.$category)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        // Go through a 2-decimal string so 12.3 becomes exactly 12.30, not 12.2999999…
        guard amount > 0, let value = Decimal(string: String(format: "%.2f", amount)) else {
            let message = "The amount must be greater than 0."
            return .result(value: message, dialog: "\(message)")
        }
        let summary = await IngestionService.shared.addExpense(amount: value, merchant: merchant, categoryName: category)
        await NotificationService.checkBudgets()
        await WidgetReloader.reload()
        return .result(value: summary, dialog: "\(summary)")
    }
}
