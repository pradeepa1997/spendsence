import SwiftData
import SwiftUI
import SpendCore

/// Shows (or edits) a transaction opened from a notification or deep link.
struct LinkedTransactionView: View {
    let link: TransactionLink

    @Environment(\.dismiss) private var dismiss

    @Query private var matches: [SpendCore.Transaction]

    init(link: TransactionLink) {
        self.link = link
        let id = link.id
        _matches = Query(filter: #Predicate<SpendCore.Transaction> { $0.id == id })
    }

    var body: some View {
        if let transaction = matches.first {
            if link.edit {
                TransactionFormView(mode: .edit(transaction))
            } else {
                TransactionDetailView(transaction: transaction)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
        } else {
            ContentUnavailableView(
                "Transaction not found",
                systemImage: "questionmark.circle",
                description: Text("It may have been removed.")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
