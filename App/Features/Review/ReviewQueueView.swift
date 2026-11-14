import SwiftData
import SwiftUI
import SpendCore

/// Low-confidence transactions not yet reviewed, plus SMS the parser couldn't read.
struct ReviewQueueView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \SpendCore.Transaction.occurredAt, order: .reverse)
    private var transactions: [SpendCore.Transaction]

    @Query(
        filter: #Predicate<RawMessage> { $0.statusRaw == "needsReview" },
        sort: \RawMessage.receivedAt,
        order: .reverse
    )
    private var reviewMessages: [RawMessage]

    @State private var messageToAdd: RawMessage?
    @State private var errorText: String?

    private var pending: [SpendCore.Transaction] { transactions.filter(\.isAwaitingReview) }
    private var unreadable: [RawMessage] { reviewMessages.filter { $0.transaction == nil } }

    var body: some View {
        Group {
            if pending.isEmpty && unreadable.isEmpty {
                ContentUnavailableView(
                    "All caught up",
                    systemImage: "checkmark.seal",
                    description: Text("Low-confidence transactions and SMS the app couldn't read show up here.")
                )
            } else {
                List {
                    if !pending.isEmpty {
                        Section {
                            ForEach(pending) { transaction in
                                NavigationLink {
                                    TransactionDetailView(transaction: transaction)
                                } label: {
                                    TransactionRow(transaction: transaction)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        run { try editor.approve(transaction) }
                                    } label: {
                                        Label("Approve", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        run { try editor.markNotATransaction(transaction) }
                                    } label: {
                                        Label("Not a transaction", systemImage: "xmark")
                                    }
                                }
                            }
                        } header: {
                            Text("Check these")
                        } footer: {
                            Text("Swipe right to approve, left if it isn't a real transaction. Tap to edit.")
                        }
                    }

                    if !unreadable.isEmpty {
                        Section("Couldn't read these SMS") {
                            ForEach(unreadable) { message in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(message.body)
                                        .font(.subheadline)
                                        .lineLimit(5)
                                    Text("\(message.sender ?? "Unknown sender") · \(message.receivedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Button("Add manually") { messageToAdd = message }
                                            .buttonStyle(.borderedProminent)
                                        Button("Dismiss") { run { try editor.dismiss(message) } }
                                            .buttonStyle(.bordered)
                                    }
                                    .font(.subheadline)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Review")
        .sheet(item: $messageToAdd) { message in
            NavigationStack {
                TransactionFormView(mode: .add(linking: message))
            }
        }
        .errorAlert($errorText)
    }

    private var editor: TransactionEditor { TransactionEditor(context: context) }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorText = error.localizedDescription }
    }
}
