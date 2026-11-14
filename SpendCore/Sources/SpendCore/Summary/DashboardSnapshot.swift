import Foundation
import SwiftData

/// Everything a widget or Siri answer needs about the current month, as a plain value.
public struct DashboardSnapshot: Sendable, Equatable {
    public let date: Date
    public let summary: SpendingSummary
    public let budgets: [BudgetStatus]
    public let awaitingReview: Int

    public var monthName: String {
        summary.interval.start.formatted(.dateTime.month(.wide))
    }

    /// Overall budget use across budgeted categories (0…∞), or nil without budgets.
    public var overallBudgetFraction: Double? {
        guard let overall = BudgetCalculator.overall(budgets), overall.budget > 0 else { return nil }
        return NSDecimalNumber(decimal: overall.spent / overall.budget).doubleValue
    }

    public static func load(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws -> DashboardSnapshot {
        let interval = SpendingSummary.month(containing: now, calendar: calendar)
        let start = interval.start
        let end = interval.end
        let transactions = try context.fetch(
            FetchDescriptor<Transaction>(predicate: #Predicate { $0.occurredAt >= start && $0.occurredAt < end })
        )
        let facts: [TransactionFact] = transactions.map { TransactionFact($0) }
        let summary = SpendingSummary.make(facts: facts, interval: interval, calendar: calendar)
        let budgets = BudgetCalculator.statuses(summary: summary, budgets: try budgetInputs(in: context))

        let threshold = ParsingPipeline.autoAcceptThreshold - 1e-9
        let awaiting = try context.fetchCount(
            FetchDescriptor<Transaction>(predicate: #Predicate { $0.confidence < threshold && $0.isReviewed == false })
        )
        return DashboardSnapshot(date: now, summary: summary, budgets: budgets, awaitingReview: awaiting)
    }

    public static func budgetInputs(in context: ModelContext) throws -> [BudgetInput] {
        try context.fetch(FetchDescriptor<TransactionCategory>()).compactMap { category in
            guard let budget = category.monthlyBudget, budget > 0 else { return nil }
            return BudgetInput(
                categoryID: category.id, name: category.name, symbol: category.symbol,
                colorHex: category.colorHex, budget: budget
            )
        }
    }
}
