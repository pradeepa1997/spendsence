import Foundation
import SwiftData

/// A bank account, card or the Cash wallet, matched on (`bankName`, `last4`) or one of its merge aliases.
@Model
public final class Account {
    @Attribute(.unique) public var id: UUID
    public var bankName: String
    public var last4: String?
    public var displayName: String
    @Relationship(deleteRule: .nullify, inverse: \Transaction.account)
    public var transactions: [Transaction] = []

    /// `AccountKind` raw value.
    public var kindRaw: String = "unknown"
    /// The user chose the kind; SMS detection no longer changes it.
    public var kindIsManual: Bool = false
    /// Credit cards: the limit, so "owed = limit − available credit" can be shown.
    public var creditLimit: Decimal?
    /// Warn on the dashboard when the balance (or available credit) drops below this.
    public var lowBalanceThreshold: Decimal?
    public var isHidden: Bool = false
    /// The user's latest "Set balance" (an opening balance or a correction) and when it applies.
    public var manualBalance: Decimal?
    public var manualBalanceAt: Date?
    /// `"<bank>|<ending>"` keys of accounts merged into this one; future SMS for them land here.
    public var mergedKeys: [String] = []

    public var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .unknown }
        set { kindRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        bankName: String,
        last4: String?,
        displayName: String? = nil,
        kind: AccountKind = .unknown
    ) {
        self.id = id
        self.bankName = bankName
        self.last4 = last4
        self.displayName = displayName ?? Account.defaultDisplayName(bankName: bankName, last4: last4)
        self.kindRaw = kind.rawValue
    }

    public static func defaultDisplayName(bankName: String, last4: String?) -> String {
        if let last4 { return "\(bankName) ••\(last4)" }
        return "\(bankName) (unknown)"
    }

    static func aliasKey(bankName: String, last4: String?) -> String {
        "\(bankName)|\(last4 ?? "")"
    }

    /// Whether an SMS for (bank, ending) belongs to this account, directly or through a merge alias.
    public func matches(bankName: String, last4: String?) -> Bool {
        if self.bankName == bankName && IngestionRules.sameAccount(self.last4, last4) { return true }
        return mergedKeys.contains { key in
            let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, String(parts[0]) == bankName else { return false }
            let aliasLast4: String? = parts[1].isEmpty ? nil : String(parts[1])
            return IngestionRules.sameAccount(aliasLast4, last4)
        }
    }
}
