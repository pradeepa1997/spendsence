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
}
