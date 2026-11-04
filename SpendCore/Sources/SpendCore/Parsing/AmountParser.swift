import Foundation

public enum AmountParser {
    /// Amounts above this are rejected as implausible.
    public static let maximum: Decimal = 100_000_000

    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Parses a transaction amount like `1,250.00`. Rejects empty, garbage, zero, negative and > 100,000,000.
    public static func parse(_ raw: String) -> Decimal? {
        guard let value = parseDecimal(raw), value > 0, value <= maximum else { return nil }
        return value
    }

    /// Like `parse` but allows zero and has no upper bound (a balance can legitimately be 0).
    public static func parseBalance(_ raw: String) -> Decimal? {
        parseDecimal(raw)
    }

    private static func parseDecimal(_ raw: String) -> Decimal? {
        let cleaned = raw.filter { $0 != "," && !$0.isWhitespace }
        let isDigit: (Character) -> Bool = { $0 >= "0" && $0 <= "9" }
        guard cleaned.contains(where: isDigit),
              cleaned.allSatisfy({ isDigit($0) || $0 == "." }),
              cleaned.filter({ $0 == "." }).count <= 1,
              let value = Decimal(string: cleaned, locale: posix),
              value >= 0
        else { return nil }
        return value
    }
}
