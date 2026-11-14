import Foundation
import SwiftData

/// A spending category. Named `TransactionCategory` because `Category` clashes with the Objective-C runtime typedef
/// that Foundation imports.
@Model
public final class TransactionCategory {
    @Attribute(.unique) public var id: UUID
    public var name: String
    /// SF Symbol name.
    public var symbol: String
    /// `#RRGGBB`
    public var colorHex: String
    /// Seeded by the app. System categories can be renamed/restyled but not deleted.
    public var isSystem: Bool
    /// Stable identifier for system categories (`groceries`, `income`, …), so renaming doesn't break categorisation.
    public var systemKey: String?
    public var sortOrder: Int
    /// Excluded from "spent" totals (Transfers: ATM withdrawals, own-account transfers).
    public var excludedFromSpending: Bool

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    public var transactions: [Transaction] = []

    @Relationship(deleteRule: .nullify, inverse: \MerchantRule.category)
    public var rules: [MerchantRule] = []

    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String,
        colorHex: String,
        isSystem: Bool = false,
        systemKey: String? = nil,
        sortOrder: Int = 0,
        excludedFromSpending: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.isSystem = isSystem
        self.systemKey = systemKey
        self.sortOrder = sortOrder
        self.excludedFromSpending = excludedFromSpending
    }
}
