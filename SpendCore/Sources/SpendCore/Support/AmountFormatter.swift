import Foundation

public enum AmountFormatter {
    /// `LKR 2,450.00`
    public static func string(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
        return "\(currency) \(number)"
    }

    /// Short form for widgets: `LKR 950`, `LKR 45.3K`, `LKR 1.25M` (no currency → `45.3K`).
    public static func compact(_ amount: Decimal, currency: String) -> String {
        let value = NSDecimalNumber(decimal: amount).doubleValue
        let magnitude = abs(value)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        let number: String
        if magnitude >= 1_000_000 {
            formatter.maximumFractionDigits = 2
            number = (formatter.string(from: NSNumber(value: value / 1_000_000)) ?? "") + "M"
        } else if magnitude >= 10_000 {
            formatter.maximumFractionDigits = 1
            number = (formatter.string(from: NSNumber(value: value / 1_000)) ?? "") + "K"
        } else {
            formatter.maximumFractionDigits = 0
            number = formatter.string(from: NSNumber(value: value.rounded())) ?? ""
        }
        return currency.isEmpty ? number : "\(currency) \(number)"
    }
}
