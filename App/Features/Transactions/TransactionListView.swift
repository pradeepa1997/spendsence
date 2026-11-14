import SwiftData
import SwiftUI
import SpendCore

struct TransactionListView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \SpendCore.Transaction.occurredAt, order: .reverse)
    private var transactions: [SpendCore.Transaction]

    @State private var searchText = ""
    @State private var showAdd = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if transactions.isEmpty {
                ContentUnavailableView(
                    "No transactions yet",
                    systemImage: "tray",
                    description: Text("Set up the Shortcuts automation, use Simulate in the More tab, or tap + to add one.")
                )
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
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
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        run { try editor.delete(transaction) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    if transaction.isAwaitingReview {
                                        Button {
                                            run { try editor.approve(transaction) }
                                        } label: {
                                            Label("Approve", systemImage: "checkmark")
                                        }
                                        .tint(.green)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Merchant, category, note or amount")
        .safeAreaInset(edge: .top) {
            LiveAutomationHealthBanner(suppressNeverReceived: transactions.isEmpty)
                .padding(.horizontal)
        }
        .navigationTitle("Transactions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdd = true
                } label: {
                    Label("Add transaction", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                TransactionFormView(mode: .add(linking: nil))
            }
        }
        .errorAlert($errorText)
    }

    private var editor: TransactionEditor { TransactionEditor(context: context) }

    private var filtered: [SpendCore.Transaction] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return transactions }
        return transactions.filter { transaction in
            let fields: [String?] = [
                transaction.merchant, transaction.originalMerchant, transaction.category?.name, transaction.note,
                transaction.account?.displayName, transaction.amountText,
            ]
            return fields.compactMap { $0?.lowercased() }.contains { $0.contains(query) }
        }
    }

    private var daySections: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.occurredAt) }
        return grouped.keys.sorted(by: >).map { day in
            DaySection(day: day, transactions: grouped[day] ?? [])
        }
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorText = error.localizedDescription }
    }
}

private struct DaySection: Identifiable {
    let day: Date
    let transactions: [SpendCore.Transaction]

    var id: Date { day }
    var title: String { day.formatted(date: .complete, time: .omitted) }
}
