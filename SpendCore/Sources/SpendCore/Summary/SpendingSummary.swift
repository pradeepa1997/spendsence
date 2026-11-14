import Foundation

/// The parts of a transaction the dashboard needs, as a plain value.
public struct TransactionFact: Sendable, Equatable {
    public var amount: Decimal
    public var currency: String
    public var type: TransactionType
    public var occurredAt: Date
    public var merchant: String?
    public var categoryID: UUID?
    public var categoryName: String
    public var categorySymbol: String
    public var categoryColorHex: String
    public var excludedFromSpending: Bool

    public init(
        amount: Decimal,
        currency: String = "LKR",
        type: TransactionType,
        occurredAt: Date,
        merchant: String? = nil,
        categoryID: UUID? = nil,
        categoryName: String = "Uncategorized",
        categorySymbol: String = "questionmark",
        categoryColorHex: String = "#8E8E93",
        excludedFromSpending: Bool = false
    ) {
        self.amount = amount
        self.currency = currency
        self.type = type
        self.occurredAt = occurredAt
        self.merchant = merchant
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.categorySymbol = categorySymbol
        self.categoryColorHex = categoryColorHex
        self.excludedFromSpending = excludedFromSpending
    }
}

/// Totals for one period. Pure; build with `make(facts:interval:)`.
///
/// Spent = debits − refunds, in `currency`, excluding categories marked `excludedFromSpending` (Transfers).
/// Income = credits outside excluded categories. Other currencies are only counted, never mixed into totals.
public struct SpendingSummary: Sendable, Equatable {
    public struct CategoryTotal: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let symbol: String
        public let colorHex: String
        public let amount: Decimal
        public let count: Int
    }

    public struct DayTotal: Sendable, Equatable, Identifiable {
        public let day: Date
        public let amount: Decimal
        public var id: Date { day }
    }

    public struct MerchantTotal: Sendable, Equatable, Identifiable {
        public let name: String
        public let amount: Decimal
        public let count: Int
        public var id: String { name }
    }

    public let interval: DateInterval
    public let currency: String
    public let totalSpent: Decimal
    public let totalIncome: Decimal
    /// Positive totals only, largest first.
    public let byCategory: [CategoryTotal]
    /// One entry per day of the interval, including zero days.
    public let byDay: [DayTotal]
    public let topMerchants: [MerchantTotal]
    /// Transactions in the interval and currency.
    public let transactionCount: Int
    /// Transactions in the interval in other currencies (not included in any total).
    public let otherCurrencyCount: Int

    public var net: Decimal { totalIncome - totalSpent }

    public static func month(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 0)
    }

    /// How much a fact adds to "spent".
    public static func spendingValue(of fact: TransactionFact) -> Decimal {
        guard !fact.excludedFromSpending else { return 0 }
        switch fact.type {
        case .debit: return fact.amount
        case .refund: return -fact.amount
        case .credit, .transfer, .unknown: return 0
        }
    }

    public static func make(
        facts: [TransactionFact],
        interval: DateInterval,
        currency: String = "LKR",
        calendar: Calendar = .current,
        topMerchantLimit: Int = 5
    ) -> SpendingSummary {
        let inInterval = facts.filter { $0.occurredAt >= interval.start && $0.occurredAt < interval.end }
        let primary = inInterval.filter { $0.currency == currency }

        var spent: Decimal = 0
        var income: Decimal = 0
        var categories: [String: (name: String, symbol: String, colorHex: String, amount: Decimal, count: Int)] = [:]
        var days: [Date: Decimal] = [:]
        var merchants: [String: (amount: Decimal, count: Int)] = [:]

        for fact in primary {
            if fact.type == .credit, !fact.excludedFromSpending {
                income += fact.amount
            }
            let value = spendingValue(of: fact)
            guard value != 0 else { continue }
            spent += value

            let categoryKey = fact.categoryID?.uuidString ?? "uncategorized"
            var category = categories[categoryKey]
                ?? (fact.categoryName, fact.categorySymbol, fact.categoryColorHex, 0, 0)
            category.amount += value
            category.count += 1
            categories[categoryKey] = category

            days[calendar.startOfDay(for: fact.occurredAt), default: 0] += value

            let merchant = fact.merchant ?? "Unknown"
            var merchantTotal = merchants[merchant] ?? (0, 0)
            merchantTotal.amount += value
            merchantTotal.count += 1
            merchants[merchant] = merchantTotal
        }

        let byCategory = categories
            .map { CategoryTotal(id: $0.key, name: $0.value.name, symbol: $0.value.symbol,
                                 colorHex: $0.value.colorHex, amount: $0.value.amount, count: $0.value.count) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.name < $1.name }

        var byDay: [DayTotal] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            byDay.append(DayTotal(day: day, amount: days[day] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let topMerchants = merchants
            .map { MerchantTotal(name: $0.key, amount: $0.value.amount, count: $0.value.count) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.name < $1.name }
            .prefix(topMerchantLimit)

        return SpendingSummary(
            interval: interval,
            currency: currency,
            totalSpent: spent,
            totalIncome: income,
            byCategory: byCategory,
            byDay: byDay,
            topMerchants: Array(topMerchants),
            transactionCount: primary.count,
            otherCurrencyCount: inInterval.count - primary.count
        )
    }
}
