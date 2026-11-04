import Foundation

/// A bank-specific SMS format, stored as data (JSON) so it can be updated without an app release.
///
/// `pattern` is matched (case-insensitive) against the *normalized* text and uses named capture groups:
/// `amount` (required), `currency`, `merchant`, `last4`, `balance`, `date`.
public struct ParserTemplate: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var bankName: String
    public var senderHints: [String]
    public var pattern: String
    public var debitKeywords: [String]
    public var creditKeywords: [String]
    /// `DateFormatter` format for the `date` group, e.g. `dd/MM/yy`. Without an hour field, the time of day
    /// is taken from when the SMS was received.
    public var dateFormat: String?

    public init(
        id: String,
        bankName: String,
        senderHints: [String],
        pattern: String,
        debitKeywords: [String],
        creditKeywords: [String],
        dateFormat: String? = nil
    ) {
        self.id = id
        self.bankName = bankName
        self.senderHints = senderHints
        self.pattern = pattern
        self.debitKeywords = debitKeywords
        self.creditKeywords = creditKeywords
        self.dateFormat = dateFormat
    }
}
