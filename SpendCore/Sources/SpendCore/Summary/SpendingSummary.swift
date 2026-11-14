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
        let inInterval: [TransactionFact] = facts.filter { fact in
            fact.occurredAt >= interval.start && fact.occurredAt < interval.end
        }
        let primary: [TransactionFact] = inInterval.filter { fact in fact.currency == currency }

        var spent: Decimal = 0
        var income: Decimal = 0
        var categoryTotals: [String: CategoryAccumulator] = [:]
        var categoryOrder: [String] = []
        var dayTotals: [Date: Decimal] = [:]
        var merchantTotals: [String: MerchantAccumulator] = [:]
        var merchantOrder: [String] = []

        for fact in primary {
            if fact.type == .credit && !fact.excludedFromSpending {
                income += fact.amount
            }
            let value: Decimal = spendingValue(of: fact)
            if value == 0 { continue }
            spent += value

            let categoryKey: String = fact.categoryID?.uuidString ?? "uncategorized"
            if categoryTotals[categoryKey] == nil {
                categoryTotals[categoryKey] = CategoryAccumulator(
                    name: fact.categoryName, symbol: fact.categorySymbol, colorHex: fact.categoryColorHex
                )
                categoryOrder.append(categoryKey)
            }
            categoryTotals[categoryKey]?.add(value)

            let day: Date = calendar.startOfDay(for: fact.occurredAt)
            dayTotals[day] = (dayTotals[day] ?? 0) + value

            let merchantName: String = fact.merchant ?? "Unknown"
            if merchantTotals[merchantName] == nil {
                merchantTotals[merchantName] = MerchantAccumulator()
                merchantOrder.append(merchantName)
            }
            merchantTotals[merchantName]?.add(value)
        }

        var byCategory: [CategoryTotal] = []
        for key in categoryOrder {
            guard let total = categoryTotals[key], total.amount > 0 else { continue }
            byCategory.append(CategoryTotal(
                id: key, name: total.name, symbol: total.symbol, colorHex: total.colorHex,
                amount: total.amount, count: total.count
            ))
        }
        byCategory.sort(by: Self.isLargerCategory)

        var byDay: [DayTotal] = []
        var day: Date = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            byDay.append(DayTotal(day: day, amount: dayTotals[day] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        var merchants: [MerchantTotal] = []
        for name in merchantOrder {
            guard let total = merchantTotals[name], total.amount > 0 else { continue }
            merchants.append(MerchantTotal(name: name, amount: total.amount, count: total.count))
        }
        merchants.sort(by: Self.isLargerMerchant)
        let topMerchants: [MerchantTotal] = Array(merchants.prefix(topMerchantLimit))

        return SpendingSummary(
            interval: interval,
            currency: currency,
            totalSpent: spent,
            totalIncome: income,
            byCategory: byCategory,
            byDay: byDay,
            topMerchants: topMerchants,
            transactionCount: primary.count,
            otherCurrencyCount: inInterval.count - primary.count
        )
    }

    // MARK: Helpers (kept as named functions so the type checker stays fast)

    private struct CategoryAccumulator {
        let name: String
        let symbol: String
        let colorHex: String
        var amount: Decimal = 0
        var count: Int = 0

        mutating func add(_ value: Decimal) {
            amount += value
            count += 1
        }
    }

    private struct MerchantAccumulator {
        var amount: Decimal = 0
        var count: Int = 0

        mutating func add(_ value: Decimal) {
            amount += value
            count += 1
        }
    }

    /// Larger amount first; ties by name.
    private static func isLargerCategory(_ lhs: CategoryTotal, _ rhs: CategoryTotal) -> Bool {
        if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
        return lhs.name < rhs.name
    }

    private static func isLargerMerchant(_ lhs: MerchantTotal, _ rhs: MerchantTotal) -> Bool {
        if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
        return lhs.name < rhs.name
    }
}
