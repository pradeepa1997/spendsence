import Foundation
import SwiftData

/// A bank card or account, matched on (`bankName`, `last4`).
@Model
public final class Account {
    @Attribute(.unique) public var id: UUID
    public var bankName: String
    public var last4: String?
    public var displayName: String
    @Relationship(deleteRule: .nullify, inverse: \Transaction.account)
    public var transactions: [Transaction] = []

    public init(id: UUID = UUID(), bankName: String, last4: String?, displayName: String? = nil) {
        self.id = id
        self.bankName = bankName
        self.last4 = last4
        self.displayName = displayName ?? Account.defaultDisplayName(bankName: bankName, last4: last4)
    }

    public static func defaultDisplayName(bankName: String, last4: String?) -> String {
        if let last4 { return "\(bankName) ••\(last4)" }
        return "\(bankName) (unknown)"
    }
}
