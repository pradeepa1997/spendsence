import Foundation

/// Sendable, read-only copies of persisted models, safe to hand across actors (tests, diagnostics).
public struct RawMessageSnapshot: Sendable, Equatable {
    public let id: UUID
    public let body: String
    public let sender: String?
    public let receivedAt: Date
    public let status: MessageStatus
    public let failureReason: String?
    public let parserVersion: Int
    public let transactionID: UUID?

    init(_ message: RawMessage) {
        id = message.id
        body = message.body
        sender = message.sender
        receivedAt = message.receivedAt
        status = message.status
        failureReason = message.failureReason
        parserVersion = message.parserVersion
        transactionID = message.transaction?.id
    }
}

public struct TransactionSnapshot: Sendable, Equatable {
    public let id: UUID
    public let amount: Decimal
    public let currency: String
    public let type: TransactionType
    public let merchant: String?
    public let occurredAt: Date
    public let balanceAfter: Decimal?
    public let confidence: Double
    public let source: TransactionSource
    public let bankName: String?
    public let last4: String?
    public let accountDisplayName: String?
    public let rawMessageID: UUID?

    init(_ transaction: Transaction) {
        id = transaction.id
        amount = transaction.amount
        currency = transaction.currency
        type = transaction.type
        merchant = transaction.merchant
        occurredAt = transaction.occurredAt
        balanceAfter = transaction.balanceAfter
        confidence = transaction.confidence
        source = transaction.source
        bankName = transaction.account?.bankName
        last4 = transaction.account?.last4
        accountDisplayName = transaction.account?.displayName
        rawMessageID = transaction.rawMessage?.id
    }
}
