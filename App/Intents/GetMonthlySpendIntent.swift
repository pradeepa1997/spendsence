import AppIntents
import Foundation
import SpendCore

/// "How much did I spend in SpendSense": this month's total and top category.
struct GetMonthlySpendIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Monthly Spending"
    static let description = IntentDescription("Tells you how much you've spent this month.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let summary = await IngestionService.shared.monthlySummary() else {
            let message = "SpendSense couldn't read its data right now."
            return .result(value: message, dialog: "\(message)")
        }
        let monthName = summary.interval.start.formatted(.dateTime.month(.wide))
        var message = "You've spent \(AmountFormatter.string(summary.totalSpent, currency: summary.currency)) in \(monthName) so far."
        if let top = summary.byCategory.first {
            message += " Most of it on \(top.name) (\(AmountFormatter.string(top.amount, currency: summary.currency)))."
        }
        return .result(value: message, dialog: "\(message)")
    }
}
