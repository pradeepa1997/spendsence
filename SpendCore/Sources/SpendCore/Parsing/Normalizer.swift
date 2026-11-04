import Foundation

public struct NormalizedMessage: Sendable, Equatable {
    /// The body exactly as received.
    public let original: String
    /// Whitespace collapsed, currency tokens unified. Parsers run on this.
    public let text: String
    /// `text` uppercased.
    public let upper: String
}

/// Stage 1: whitespace + currency normalization. Commas are deliberately left alone (see `AmountParser`).
public enum Normalizer {
    public static let currencyCodes = ["LKR", "USD", "EUR", "GBP", "INR", "AUD", "SGD"]

    /// `Rs.`, `Rs`, `LKR.`, `LKR`, `SLRs` (any case, word-bounded) → `LKR`.
    /// The trailing dot is only consumed when an amount follows, so a sentence-ending "in LKR." keeps its period.
    private static let localCurrencyAlias = CompiledRegex(#"(?<![A-Za-z])(?:SLRs|LKR|Rs)(?:\.(?=\s*\d))?(?![A-Za-z])"#)

    /// A currency code glued to a digit, e.g. `LKR1,250.00`.
    private static let gluedCurrency = CompiledRegex(
        #"(?<![A-Za-z])("# + currencyCodes.joined(separator: "|") + #")(?=\d)"#
    )

    public static func normalize(_ body: String) -> NormalizedMessage {
        var text = body.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        text = localCurrencyAlias.replacingMatches(in: text, with: "LKR")
        text = gluedCurrency.replacingMatches(in: text, with: "$1 ")
        return NormalizedMessage(original: body, text: text, upper: text.uppercased())
    }
}
