import SwiftUI
import SpendCore

struct TransactionDetailView: View {
    let transaction: SpendCore.Transaction

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var errorText: String?
    /// Set before deleting so the view stops reading the model.
    @State private var isRemoved = false

    var body: some View {
        if isRemoved {
            ContentUnavailableView("Transaction removed", systemImage: "trash")
        } else {
            details
        }
    }

    private var details: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    CategoryIcon(category: transaction.category, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transaction.merchant ?? "Unknown")
                            .font(.title3.bold())
                        Text(transaction.category?.name ?? "Uncategorized")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(transaction.signedAmountText)
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(transaction.amountColor)
                }
                if transaction.isAwaitingReview {
                    Button {
                        run { try editor.approve(transaction) }
                    } label: {
                        Label("Looks right – approve", systemImage: "checkmark.circle")
                    }
                }
            }

            Section("Details") {
                LabeledContent("Type", value: transaction.type.label)
                LabeledContent("Account", value: transaction.account?.displayName ?? "—")
                LabeledContent("Date") {
                    Text(transaction.occurredAt, format: .dateTime)
                }
                if let original = transaction.originalMerchant, original != transaction.merchant {
                    LabeledContent("Bank's merchant text", value: original)
                }
                if let note = transaction.note {
                    LabeledContent("Note", value: note)
                }
                if let balance = transaction.balanceAfter {
                    LabeledContent("Balance after", value: AmountFormatter.string(balance, currency: transaction.currency))
                }
                LabeledContent("Source", value: transaction.source.rawValue.capitalized)
                LabeledContent("Confidence") {
                    HStack(spacing: 6) {
                        Text(transaction.confidence, format: .percent.precision(.fractionLength(0)))
                        if transaction.isAwaitingReview {
                            ReviewBadge()
                        }
                    }
                }
            }

            if let raw = transaction.rawMessage {
                Section("Original SMS") {
                    Text(raw.body)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    LabeledContent("Sender", value: raw.sender ?? "—")
                    LabeledContent("Received") {
                        Text(raw.receivedAt, format: .dateTime)
                    }
                }
            }

            Section {
                if transaction.rawMessage != nil {
                    Button("Not a transaction", role: .destructive) {
                        remove(markNotATransaction: true)
                    }
                }
                Button("Delete transaction", role: .destructive) {
                    confirmDelete = true
                }
            } footer: {
                if transaction.rawMessage != nil {
                    Text("“Not a transaction” removes it and keeps the SMS in Messages as ignored.")
                }
            }
        }
        .navigationTitle(transaction.merchant ?? "Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { showEdit = true }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                TransactionFormView(mode: .edit(transaction))
            }
        }
        .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { remove(markNotATransaction: false) }
        }
        .errorAlert($errorText)
    }

    private var editor: TransactionEditor { TransactionEditor(context: context) }

    private func remove(markNotATransaction: Bool) {
        let target = transaction
        isRemoved = true
        do {
            if markNotATransaction {
                try editor.markNotATransaction(target)
            } else {
                try editor.delete(target)
            }
            dismiss()
        } catch {
            isRemoved = false
            errorText = error.localizedDescription
        }
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorText = error.localizedDescription }
    }
}
