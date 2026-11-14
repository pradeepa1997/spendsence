import Foundation

/// Output of a parser. Pure value type, no SwiftData.
public struct ParsedTransaction: Sendable, Equatable {
    public var amount: Decimal
    public var currency: String
    public var type: TransactionType
    public var merchant: String?
    public var last4: String?
    public var balanceAfter: Decimal?
    public var occurredAt: Date?
    public var bankName: String?
    public var confidence: Double
    public var matchedTemplateID: String?
    /// What kind of account the SMS is about, when the template or wording says so.
    public var accountKind: AccountKind?

    public init(
        amount: Decimal,
        currency: String = "LKR",
        type: TransactionType,
        merchant: String? = nil,
        last4: String? = nil,
        balanceAfter: Decimal? = nil,
        occurredAt: Date? = nil,
        bankName: String? = nil,
        confidence: Double,
        matchedTemplateID: String? = nil,
        accountKind: AccountKind? = nil
    ) {
        self.amount = amount
        self.currency = currency
        self.type = type
        self.merchant = merchant
        self.last4 = last4
        self.balanceAfter = balanceAfter
        self.occurredAt = occurredAt
        self.bankName = bankName
        self.confidence = confidence
        self.matchedTemplateID = matchedTemplateID
        self.accountKind = accountKind
    }
}
