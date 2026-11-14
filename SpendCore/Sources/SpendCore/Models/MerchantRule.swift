import Foundation
import SwiftData

/// Something the user taught the app about a merchant: "LPAY TFR" → rename to "LankaPay Transfer", category Transfers.
/// Applied at ingest to future SMS whose parsed merchant matches `pattern`.
@Model
public final class MerchantRule {
    @Attribute(.unique) public var id: UUID
    /// A `MerchantKey` (uppercase words). Matches merchants containing these whole words.
    public var pattern: String
    /// Display name to use instead of the bank's merchant text.
    public var renameTo: String?
    /// Inverse of `TransactionCategory.rules`.
    public var category: TransactionCategory?
    public var hitCount: Int
    public var createdAt: Date

    public init(id: UUID = UUID(), pattern: String, renameTo: String? = nil, hitCount: Int = 0, createdAt: Date = .now) {
        self.id = id
        self.pattern = pattern
        self.renameTo = renameTo
        self.hitCount = hitCount
        self.createdAt = createdAt
    }
}
