import SwiftData
import SwiftUI
import SpendCore

struct TransactionListView: View {
    @Query(sort: \SpendCore.Transaction.occurredAt, order: .reverse)
    private var transactions: [SpendCore.Transaction]

    /// The latest message delivered by the Shortcuts automation (Simulate-tab messages don't count).
    @Query(TransactionListView.latestAutomationMessage)
    private var latestAutomationMessages: [RawMessage]

    nonisolated private static var latestAutomationMessage: FetchDescriptor<RawMessage> {
        let sms = TransactionSource.sms.rawValue
        var descriptor = FetchDescriptor<RawMessage>(
            predicate: #Predicate { $0.sourceRaw == sms },
            sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    private var health: AutomationHealth {
        let health = AutomationHealth.evaluate(lastSMSAt: latestAutomationMessages.first?.receivedAt)
        // With an empty list, the empty state already explains the setup; don't stack a banner on top.
        if health == .neverReceived && transactions.isEmpty { return .healthy }
        return health
    }

    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    ContentUnavailableView(
                        "No transactions yet",
                        systemImage: "tray",
                        description: Text("Use the Simulate tab or set up the Shortcuts automation.")
                    )
                } else {
                    List {
                        ForEach(daySections) { section in
                            Section(section.title) {
                                ForEach(section.transactions) { transaction in
                                    NavigationLink {
                                        TransactionDetailView(transaction: transaction)
                                    } label: {
                                        TransactionRow(transaction: transaction)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                AutomationHealthBanner(health: health)
            }
            .navigationTitle("Transactions")
        }
    }

    private var daySections: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions) { calendar.startOfDay(for: $0.occurredAt) }
        return grouped.keys.sorted(by: >).map { day in
            DaySection(day: day, transactions: grouped[day] ?? [])
        }
    }
}

private struct DaySection: Identifiable {
    let day: Date
    let transactions: [SpendCore.Transaction]

    var id: Date { day }
    var title: String { day.formatted(date: .complete, time: .omitted) }
}

private struct TransactionRow: View {
    let transaction: SpendCore.Transaction

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(transaction.merchant ?? "Unknown")
                        .font(.headline)
                    if transaction.needsReview {
                        ReviewBadge()
                    }
                }
                Text(transaction.account?.displayName ?? "No account")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
}
