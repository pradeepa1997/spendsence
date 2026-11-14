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
