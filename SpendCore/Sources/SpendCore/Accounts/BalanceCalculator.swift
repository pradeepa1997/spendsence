import Foundation

/// One point on an account's timeline.
public struct BalanceEvent: Sendable, Equatable {
    public var date: Date
    /// Tie-breaker for events at the same date (e.g. creation time).
    public var sequence: Date
    /// What the event does to the balance when no balance was reported (debit −, credit/refund +).
    public var effect: Decimal
    /// A balance stated by the bank SMS (after this transaction) or set by the user. Resets the running balance.
    public var reportedBalance: Decimal?
    public var isManual: Bool

    public init(date: Date, sequence: Date? = nil, effect: Decimal, reportedBalance: Decimal? = nil, isManual: Bool = false) {
        self.date = date
        self.sequence = sequence ?? date
        self.effect = effect
        self.reportedBalance = reportedBalance
        self.isManual = isManual
    }

    /// Effect of a transaction on money in an account, or on available credit on a card (same signs).
    public static func effect(of type: TransactionType, amount: Decimal) -> Decimal {
        switch type {
        case .debit, .transfer: return -amount
        case .credit, .refund: return amount
        case .unknown: return 0
        }
    }
}

public struct BalancePoint: Sendable, Equatable, Identifiable {
    public let date: Date
    public let value: Decimal
    public var id: Date { date }
}

public struct AccountBalance: Sendable, Equatable {
    public enum Source: String, Sendable, Equatable {
        /// From the most recent bank SMS that stated a balance.
        case reported
        /// From the user's "Set balance".
        case manual
        /// Added up from transactions only (Cash with no opening balance).
        case computed
        /// Nothing known yet.
        case none
    }

    /// Money in the account, or available credit for a credit card. Nil when unknown.
    public let value: Decimal?
    /// When the last reported/manual balance applied.
    public let asOf: Date?
    public let source: Source
    /// Transactions since the last reported/manual balance; > 0 means `value` is an estimate.
    public let pendingCount: Int
    public let kind: AccountKind
    public let creditLimit: Decimal?
    /// Oldest first; one point per event from the first known balance on.
    public let history: [BalancePoint]

    public var isEstimated: Bool { pendingCount > 0 || source == .computed }

    /// Credit cards with a limit: limit − available credit (never negative).
    public var amountOwed: Decimal? {
        guard kind == .creditCard, let creditLimit, let value else { return nil }
        let owed = creditLimit - value
        return owed > 0 ? owed : 0
    }

    /// Credit cards with a limit: owed ÷ limit, 0…1.
    public var utilization: Double? {
        guard let amountOwed, let creditLimit, creditLimit > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: amountOwed / creditLimit).doubleValue
        return min(max(ratio, 0), 1)
    }

    public func isBelow(_ threshold: Decimal?) -> Bool {
        guard let threshold, let value else { return false }
        return value < threshold
    }
}

/// Walks an account's timeline: a reported/manual balance resets the running value, other transactions adjust it.
public enum BalanceCalculator {
    public static func balance(
        kind: AccountKind,
        events: [BalanceEvent],
        creditLimit: Decimal? = nil
    ) -> AccountBalance {
        let ordered: [BalanceEvent] = events.sorted(by: isEarlier)

        var running: Decimal? = kind == .cash ? 0 : nil
        var source: AccountBalance.Source = kind == .cash ? .computed : .none
        var asOf: Date?
        var pending = 0
        var history: [BalancePoint] = []

        for event in ordered {
            if let reported = event.reportedBalance {
                running = reported
                source = event.isManual ? .manual : .reported
                asOf = event.date
                pending = 0
            } else if let current = running {
                running = current + event.effect
                pending += 1
            }
            if let value = running {
                history.append(BalancePoint(date: event.date, value: value))
            }
        }

        if source == .computed {
            pending = 0 // cash without an opening balance: "computed", not "pending since"
        }

        return AccountBalance(
            value: running,
            asOf: asOf,
            source: source,
            pendingCount: pending,
            kind: kind,
            creditLimit: creditLimit,
            history: history
        )
    }

    private static func isEarlier(_ lhs: BalanceEvent, _ rhs: BalanceEvent) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
        // A manual balance at the same moment wins (it's applied last).
        return !lhs.isManual && rhs.isManual
    }
}

/// Totals across accounts for the Accounts screen and dashboard.
public struct AccountsOverview: Sendable, Equatable {
    /// Sum of known balances of bank accounts, debit cards, cash and unknown-kind accounts.
    public let moneyInAccounts: Decimal
    /// Sum of amount owed on credit cards that have a limit.
    public let owedOnCards: Decimal
    /// Credit cards without a limit (owed can't be worked out).
    public let cardsWithoutLimit: Int
    /// Accounts with no balance known yet.
    public let unknownBalanceCount: Int

    public static func make(_ balances: [AccountBalance]) -> AccountsOverview {
        var money: Decimal = 0
        var owed: Decimal = 0
        var withoutLimit = 0
        var unknown = 0
        for balance in balances {
            if balance.kind == .creditCard {
                if let amountOwed = balance.amountOwed {
                    owed += amountOwed
                } else {
                    withoutLimit += 1
                }
            } else if let value = balance.value {
                money += value
            } else {
                unknown += 1
            }
        }
        return AccountsOverview(
            moneyInAccounts: money, owedOnCards: owed, cardsWithoutLimit: withoutLimit, unknownBalanceCount: unknown
        )
    }
}
