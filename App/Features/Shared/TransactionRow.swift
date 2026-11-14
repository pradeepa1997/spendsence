import SwiftUI
import SpendCore

struct TransactionRow: View {
    let transaction: SpendCore.Transaction

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: transaction.category)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(transaction.merchant ?? "Unknown")
                        .font(.headline)
                        .lineLimit(1)
                    if transaction.isAwaitingReview {
                        ReviewBadge()
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(transaction.signedAmountText)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(transaction.amountColor)
                Text(transaction.occurredAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        [transaction.category?.name, transaction.account?.displayName]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
