import Foundation
import SwiftData

/// A money movement. `amount` is always positive; direction comes from `type`.
///
/// Note: SwiftUI also declares a `Transaction` type. In files that import both SwiftUI and SpendCore,
/// refer to this one as `SpendCore.Transaction`.
@Model
public final class Transaction {
    @Attribute(.unique) public var id: UUID
    public var amount: Decimal
    public var currency: String
    public var typeRaw: String
    /// Display name (may have been renamed by the user or a merchant rule).
    public var merchant: String?
    /// The merchant exactly as parsed from the SMS. Merchant rules match on this.
    public var originalMerchant: String?
    public var occurredAt: Date
    public var balanceAfter: Decimal?
    public var confidence: Double
    public var sourceRaw: String
    /// Inverse of `TransactionCategory.transactions`.
    public var category: TransactionCategory?
    /// The user picked this category for this transaction; rules applied to past transactions leave it alone.
    public var categoryIsManual: Bool = false
    public var note: String?
    public var isUserEdited: Bool
    /// The user approved or edited this transaction, so it no longer shows in the review queue.
    public var isReviewed: Bool = false
    public var createdAt: Date
    public var account: Account?
    @Relationship(deleteRule: .nullify, inverse: \RawMessage.transaction)
    public var rawMessage: RawMessage?

    public var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .unknown }
        set { typeRaw = newValue.rawValue }
    }

    public var source: TransactionSource {
        get { TransactionSource(rawValue: sourceRaw) ?? .sms }
        set { sourceRaw = newValue.rawValue }
    }

    /// True when the parser was not confident enough to auto-accept this transaction.
    public var needsReview: Bool {
        confidence < ParsingPipeline.autoAcceptThreshold - 1e-9
    }

    /// Low confidence and not yet approved or edited by the user.
    public var isAwaitingReview: Bool {
        needsReview && !isReviewed
    }

    public init(
        id: UUID = UUID(),
        amount: Decimal,
        currency: String = "LKR",
        type: TransactionType,
        merchant: String? = nil,
        occurredAt: Date,
        balanceAfter: Decimal? = nil,
        confidence: Double,
        source: TransactionSource,
        note: String? = nil,
        isUserEdited: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.typeRaw = type.rawValue
        self.merchant = merchant
        self.originalMerchant = merchant
        self.occurredAt = occurredAt
        self.balanceAfter = balanceAfter
        self.confidence = confidence
        self.sourceRaw = source.rawValue
        self.note = note
        self.isUserEdited = isUserEdited
        self.createdAt = createdAt
    }
}
