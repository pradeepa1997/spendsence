import Foundation
import SwiftUI
import SpendCore

extension SpendCore.Transaction {
    var amountText: String {
        AmountFormatter.string(amount, currency: currency)
    }

    var signedAmountText: String {
        switch type {
        case .debit: "−" + amountText
        case .credit, .refund: "+" + amountText
        case .transfer, .unknown: amountText
        }
    }

    /// Red for debits, green for credits and refunds.
    var amountColor: Color {
        switch type {
        case .debit: .red
        case .credit, .refund: .green
        case .transfer, .unknown: .primary
        }
    }
}

extension MessageStatus {
    var label: String {
        switch self {
        case .pending: "Pending"
        case .parsed: "Parsed"
        case .ignored: "Ignored"
        case .needsReview: "Review"
        case .duplicate: "Duplicate"
        case .failed: "Failed"
        }
    }

    var color: Color {
        switch self {
        case .pending: .gray
        case .parsed: .green
        case .ignored: .secondary
        case .needsReview: .orange
        case .duplicate: .purple
        case .failed: .red
        }
    }
}

struct StatusPill: View {
    let status: MessageStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.15), in: Capsule())
    }
}

struct ReviewBadge: View {
    var body: some View {
        Text("Review")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.orange)
            .background(Color.orange.opacity(0.15), in: Capsule())
    }
}

extension TransactionType {
    /// User-facing name.
    var label: String {
        switch self {
        case .debit: "Expense"
        case .credit: "Income"
        case .refund: "Refund"
        case .transfer: "Transfer"
        case .unknown: "Unknown"
        }
    }

    /// The types a user can pick when adding or editing.
    static let editable: [TransactionType] = [.debit, .credit, .refund, .transfer]
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    /// `2450`, `2450.5`: for pre-filling a text field.
    var plainString: String { NSDecimalNumber(decimal: self).stringValue }
}

extension Color {
    /// `#RRGGBB`; invalid input gives grey.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt64(digits, radix: 16) else {
            self = .gray
            return
        }
        let red: Double = Double((value >> 16) & 0xFF) / 255.0
        let green: Double = Double((value >> 8) & 0xFF) / 255.0
        let blue: Double = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

struct CategoryIconView: View {
    let symbol: String
    let colorHex: String
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: colorHex), in: Circle())
    }
}

struct CategoryIcon: View {
    let category: TransactionCategory?
    var size: CGFloat = 32

    var body: some View {
        CategoryIconView(
            symbol: category?.symbol ?? "questionmark",
            colorHex: category?.colorHex ?? "#8E8E93",
            size: size
        )
    }
}

/// Presents an error message from an optional string.
struct ErrorAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            "Something went wrong",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        modifier(ErrorAlert(message: message))
    }
}

extension AccountKind {
    var label: String {
        switch self {
        case .bankAccount: "Bank account"
        case .debitCard: "Debit card"
        case .creditCard: "Credit card"
        case .cash: "Cash"
        case .unknown: "Account"
        }
    }

    var symbol: String {
        switch self {
        case .bankAccount: "building.columns.fill"
        case .debitCard: "creditcard"
        case .creditCard: "creditcard.fill"
        case .cash: "banknote.fill"
        case .unknown: "questionmark.square.dashed"
        }
    }

    var colorHex: String {
        switch self {
        case .bankAccount: "#007AFF"
        case .debitCard: "#30B0C7"
        case .creditCard: "#AF52DE"
        case .cash: "#34C759"
        case .unknown: "#8E8E93"
        }
    }

    /// The kinds a user can pick (unknown is only a starting state).
    static let editable: [AccountKind] = [.bankAccount, .debitCard, .creditCard, .cash]
}

enum BalanceText {
    static let currency = "LKR"

    /// The main figure: balance, or available credit for credit cards.
    static func primary(_ balance: AccountBalance) -> String {
        guard let value = balance.value else { return "—" }
        return AmountFormatter.string(value, currency: currency)
    }

    /// e.g. "Available credit · as of 14 Nov, 17:46 · estimated (+2)".
    static func caption(_ balance: AccountBalance) -> String {
        var parts: [String] = []
        if balance.kind == .creditCard, balance.value != nil {
            parts.append("Available credit")
        }
        switch balance.source {
        case .none:
            parts.append("No balance yet")
        case .computed:
            parts.append("From your entries")
        case .reported:
            if let asOf = balance.asOf { parts.append("as of \(asOf.formatted(date: .abbreviated, time: .shortened))") }
        case .manual:
            if let asOf = balance.asOf { parts.append("set by you \(asOf.formatted(date: .abbreviated, time: .omitted))") }
        }
        if balance.pendingCount > 0 {
            parts.append("estimated (+\(balance.pendingCount))")
        }
        return parts.joined(separator: " · ")
    }
}

struct AccountIcon: View {
    let kind: AccountKind
    var size: CGFloat = 32

    var body: some View {
        CategoryIconView(symbol: kind.symbol, colorHex: kind.colorHex, size: size)
    }
}

/// Parses user-typed amounts: commas allowed, an optional leading minus (overdrafts), empty → nil.
enum AmountInput {
    static func parse(_ text: String, allowNegative: Bool = false) -> Decimal? {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var negative = false
        if allowNegative, trimmed.hasPrefix("-") {
            negative = true
            trimmed.removeFirst()
        }
        guard let value = AmountParser.parseBalance(trimmed) else { return nil }
        return negative ? -value : value
    }
}
