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
