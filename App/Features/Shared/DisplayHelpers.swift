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
