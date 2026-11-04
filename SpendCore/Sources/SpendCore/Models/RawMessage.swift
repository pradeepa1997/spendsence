import Foundation
import SwiftData

/// An SMS exactly as received. Always persisted before parsing so the text is never lost.
@Model
public final class RawMessage {
    @Attribute(.unique) public var id: UUID
    public var body: String
    public var sender: String?
    public var receivedAt: Date
    public var statusRaw: String
    public var parserVersion: Int
    public var failureReason: String?
    /// SHA-256 (hex) of the trimmed body; used for exact-duplicate detection.
    public var bodyHash: String
    /// Inverse of `Transaction.rawMessage`.
    public var transaction: Transaction?

    public var status: MessageStatus {
        get { MessageStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        body: String,
        sender: String?,
        receivedAt: Date,
        status: MessageStatus = .pending,
        parserVersion: Int = ParsingPipeline.version
    ) {
        self.id = id
        self.body = body
        self.sender = sender
        self.receivedAt = receivedAt
        self.statusRaw = status.rawValue
        self.parserVersion = parserVersion
        self.failureReason = nil
        self.bodyHash = BodyHasher.hash(body)
    }
}
