import Foundation

public enum TransactionType: String, Codable, Sendable, CaseIterable {
    case debit, credit, refund, transfer, unknown
}

public enum MessageStatus: String, Codable, Sendable, CaseIterable {
    case pending, parsed, ignored, needsReview, duplicate, failed
}

public enum TransactionSource: String, Codable, Sendable, CaseIterable {
    case sms, manual, simulated
}

/// What an account is. Detected from the SMS template, refinable by the user.
public enum AccountKind: String, Codable, Sendable, CaseIterable {
    case bankAccount, debitCard, creditCard, cash, unknown

    /// For credit cards the balance is *available credit*; for everything else it's money you have.
    public var balanceIsAvailableCredit: Bool { self == .creditCard }

    /// Combines the current kind with one detected from a new SMS. Never downgrades: unknown → anything;
    /// a debit card becomes a bank account once an account SMS for it arrives (the card is just a view of it).
    public func refined(with detected: AccountKind?) -> AccountKind {
        guard let detected, detected != .unknown, detected != self else { return self }
        switch (self, detected) {
        case (.unknown, _): return detected
        case (.debitCard, .bankAccount): return .bankAccount
        default: return self
        }
    }
}
