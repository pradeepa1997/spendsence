import SwiftUI
import SpendCore

/// Read-only in Phase 1.
struct TransactionDetailView: View {
    let transaction: SpendCore.Transaction

    var body: some View {
        List {
            Section("Amount") {
                LabeledContent("Amount") {
                    Text(transaction.signedAmountText)
                        .foregroundStyle(transaction.amountColor)
                }
                LabeledContent("Type", value: transaction.type.rawValue.capitalized)
                LabeledContent("Currency", value: transaction.currency)
                if let balance = transaction.balanceAfter {
                    LabeledContent("Balance after", value: AmountFormatter.string(balance, currency: transaction.currency))
                }
            }

            Section("Details") {
                LabeledContent("Merchant", value: transaction.merchant ?? "Unknown")
                LabeledContent("Account", value: transaction.account?.displayName ?? "—")
                LabeledContent("Occurred") {
                    Text(transaction.occurredAt, format: .dateTime)
                }
                LabeledContent("Category", value: transaction.categoryName ?? "—")
                LabeledContent("Source", value: transaction.source.rawValue.capitalized)
                LabeledContent("Confidence") {
                    HStack(spacing: 6) {
                        Text(transaction.confidence, format: .percent.precision(.fractionLength(0)))
                        if transaction.needsReview {
                            ReviewBadge()
                        }
                    }
                }
                LabeledContent("Logged") {
                    Text(transaction.createdAt, format: .dateTime)
                }
            }

            Section("Original SMS") {
                if let raw = transaction.rawMessage {
                    Text(raw.body)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    LabeledContent("Sender", value: raw.sender ?? "—")
                    LabeledContent("Received") {
                        Text(raw.receivedAt, format: .dateTime)
                    }
                } else {
                    Text("No linked message")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(transaction.merchant ?? "Transaction")
        .navigationBarTitleDisplayMode(.inline)
    }
}
