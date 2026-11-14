import Foundation

/// A bank-specific SMS format, stored as data (JSON) so it can be updated without an app release.
///
/// `pattern` is matched (case-insensitive) against the *normalized* text and uses named capture groups:
/// `amount` (required), `currency`, `merchant`, `last4` (the last 2–4 visible digits), `balance`, `date`, `time`.
public struct ParserTemplate: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var bankName: String
    public var senderHints: [String]
    public var pattern: String
    public var debitKeywords: [String]
    public var creditKeywords: [String]
    /// `DateFormatter` format for the `date` group, e.g. `dd/MM/yy`. Month names in any case are accepted
    /// (`NOV`, `Nov`). Without a time, the time of day is taken from when the SMS was received.
    public var dateFormat: String?
    /// `DateFormatter` format for the `time` group, e.g. `HH:mm` or `hh:mm:ss a`. Used together with `dateFormat`.
    public var timeFormat: String?
    /// `AccountKind` raw value (`bankAccount`, `debitCard`, `creditCard`). Kept as a string so an unknown value in
    /// the JSON can't break loading the whole template file.
    public var accountKind: String?

    public init(
        id: String,
        bankName: String,
        senderHints: [String],
        pattern: String,
        debitKeywords: [String],
        creditKeywords: [String],
        dateFormat: String? = nil,
        timeFormat: String? = nil,
        accountKind: String? = nil
    ) {
        self.id = id
        self.bankName = bankName
        self.senderHints = senderHints
        self.pattern = pattern
        self.debitKeywords = debitKeywords
        self.creditKeywords = creditKeywords
        self.dateFormat = dateFormat
        self.timeFormat = timeFormat
        self.accountKind = accountKind
    }
}
