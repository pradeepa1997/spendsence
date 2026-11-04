import Foundation
import SwiftData

/// A parsed money movement. `amount` is always positive; direction comes from `type`.
///
/// Note: SwiftUI also declares a `Transaction` type. In files that import both SwiftUI and SpendCore,
/// refer to this one as `SpendCore.Transaction`.
@Model
public final class Transaction {
    @Attribute(.unique) public var id: UUID
    public var amount: Decimal
    public var currency: String
    public var typeRaw: String
    public var merchant: String?
    public var occurredAt: Date
    public var balanceAfter: Decimal?
    public var confidence: Double
    public var sourceRaw: String
    /// Phase 1 placeholder; replaced by a Category model later.
    public var categoryName: String?
    public var isUserEdited: Bool
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
        categoryName: String? = nil,
        isUserEdited: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.typeRaw = type.rawValue
        self.merchant = merchant
        self.occurredAt = occurredAt
        self.balanceAfter = balanceAfter
        self.confidence = confidence
        self.sourceRaw = source.rawValue
        self.categoryName = categoryName
        self.isUserEdited = isUserEdited
        self.createdAt = createdAt
    }
}
