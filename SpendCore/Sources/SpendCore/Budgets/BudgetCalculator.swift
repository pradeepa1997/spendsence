import Foundation

/// A category with a budget, as a plain value.
public struct BudgetInput: Sendable, Equatable {
    public let categoryID: UUID
    public let name: String
    public let symbol: String
    public let colorHex: String
    public let budget: Decimal

    public init(categoryID: UUID, name: String, symbol: String, colorHex: String, budget: Decimal) {
        self.categoryID = categoryID
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.budget = budget
    }
}

public struct BudgetStatus: Sendable, Equatable, Identifiable {
    public enum Level: String, Sendable, Equatable, Comparable {
        case ok, warning, over

        private var rank: Int {
            switch self {
            case .ok: 0
            case .warning: 1
            case .over: 2
            }
        }

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rank < rhs.rank }
    }

    public let categoryID: UUID
    public let name: String
    public let symbol: String
    public let colorHex: String
    public let budget: Decimal
    public let spent: Decimal
    public var id: UUID { categoryID }

    /// Spent ÷ budget; can exceed 1.
    public var fraction: Double {
        guard budget > 0 else { return 0 }
        return NSDecimalNumber(decimal: spent / budget).doubleValue
    }

    /// What's left; negative when over budget.
    public var remaining: Decimal { budget - spent }

    public var level: Level {
        if fraction >= 1 { return .over }
        if fraction >= BudgetCalculator.warningFraction { return .warning }
        return .ok
    }
}

public enum BudgetCalculator {
    public static let warningFraction = 0.8

    /// One status per budgeted category, most used first. Spending comes from the summary's category totals.
    public static func statuses(summary: SpendingSummary, budgets: [BudgetInput]) -> [BudgetStatus] {
        var spentByCategory: [String: Decimal] = [:]
        for total in summary.byCategory {
            spentByCategory[total.id] = total.amount
        }
        var statuses: [BudgetStatus] = []
        for input in budgets where input.budget > 0 {
            statuses.append(BudgetStatus(
                categoryID: input.categoryID,
                name: input.name,
                symbol: input.symbol,
                colorHex: input.colorHex,
                budget: input.budget,
                spent: spentByCategory[input.categoryID.uuidString] ?? 0
            ))
        }
        statuses.sort(by: isMoreUsed)
        return statuses
    }

    /// Budget and spent across all budgeted categories (for an overall gauge). Nil when there are no budgets.
    public static func overall(_ statuses: [BudgetStatus]) -> (spent: Decimal, budget: Decimal)? {
        guard !statuses.isEmpty else { return nil }
        var spent: Decimal = 0
        var budget: Decimal = 0
        for status in statuses {
            spent += status.spent
            budget += status.budget
        }
        return (spent, budget)
    }

    private static func isMoreUsed(_ lhs: BudgetStatus, _ rhs: BudgetStatus) -> Bool {
        if lhs.fraction != rhs.fraction { return lhs.fraction > rhs.fraction }
        return lhs.name < rhs.name
    }
}

/// A budget notification to send.
public struct BudgetAlert: Sendable, Equatable {
    /// 80 or 100.
    public let threshold: Int
    public let status: BudgetStatus
    /// Keys to record as sent (the 100% alert also covers 80%).
    public let keys: [String]
}

/// Decides which budget alerts to send: once per category, per month, per threshold.
public enum BudgetAlertPlanner {
    public static let thresholds = [100, 80]

    /// `yyyy-MM` in the given calendar.
    public static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }

    public static func key(monthKey: String, categoryID: UUID, threshold: Int) -> String {
        "\(monthKey)|\(categoryID.uuidString)|\(threshold)"
    }

    /// For each status, the highest threshold reached, unless already sent.
    public static func alerts(for statuses: [BudgetStatus], monthKey: String, alreadySent: Set<String>) -> [BudgetAlert] {
        var alerts: [BudgetAlert] = []
        for status in statuses {
            let reached = thresholds.filter { status.fraction * 100 >= Double($0) }
            guard let highest = reached.first else { continue }
            let highestKey = key(monthKey: monthKey, categoryID: status.categoryID, threshold: highest)
            guard !alreadySent.contains(highestKey) else { continue }
            let keys = reached.map { key(monthKey: monthKey, categoryID: status.categoryID, threshold: $0) }
            alerts.append(BudgetAlert(threshold: highest, status: status, keys: keys))
        }
        return alerts
    }

    /// Drops sent keys from earlier months so the stored set stays small.
    public static func pruned(_ sent: Set<String>, keepingMonth monthKey: String) -> Set<String> {
        sent.filter { $0.hasPrefix(monthKey + "|") }
    }
}
