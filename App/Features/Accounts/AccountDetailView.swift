import Charts
import SwiftUI
import SpendCore

struct AccountDetailView: View {
    enum SheetKind: String, Identifiable {
        case edit, setBalance, merge
        var id: String { rawValue }
    }

    let account: Account

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var sheet: SheetKind?
    @State private var errorText: String?
    /// Set when this account was merged away, so the view stops reading the deleted model.
    @State private var isRemoved = false

    var body: some View {
        Group {
            if isRemoved {
                ContentUnavailableView("Account merged", systemImage: "arrow.triangle.merge")
            } else {
                details
            }
        }
        .sheet(item: $sheet, onDismiss: {
            if isRemoved { dismiss() }
        }) { kind in
            NavigationStack {
                if isRemoved {
                    EmptyView()
                } else {
                    switch kind {
                    case .edit:
                        AccountFormView(account: account)
                    case .setBalance:
                        SetBalanceView(account: account)
                    case .merge:
                        MergeAccountView(account: account) { isRemoved = true }
                    }
                }
            }
        }
        .errorAlert($errorText)
    }

    private var details: some View {
        let balance = account.balance
        let recent = account.transactions.sorted { $0.occurredAt > $1.occurredAt }

        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        AccountIcon(kind: account.kind, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.kind.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(BalanceText.primary(balance))
                                .font(.title.bold().monospacedDigit())
                                .foregroundStyle(balance.isBelow(account.lowBalanceThreshold) ? Color.orange : Color.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    Text(BalanceText.caption(balance))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if balance.isBelow(account.lowBalanceThreshold), let threshold = account.lowBalanceThreshold {
                        Label("Below your alert of \(AmountFormatter.string(threshold, currency: BalanceText.currency))",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)

                if account.kind == .creditCard {
                    creditCardRows(balance)
                }
            }

            if balance.history.count >= 2 {
                Section("Balance over time") {
                    Chart {
                        // Offsets as ids: two points can share a timestamp.
                        ForEach(Array(balance.history.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Balance", point.value.doubleValue)
                            )
                            .interpolationMethod(.stepEnd)
                        }
                    }
                    .frame(height: 180)
                }
            }

            Section("Details") {
                LabeledContent("Bank", value: account.bankName)
                LabeledContent("Ending", value: account.last4.map { "••\($0)" } ?? "—")
                if let threshold = account.lowBalanceThreshold {
                    LabeledContent("Low-balance alert", value: AmountFormatter.string(threshold, currency: BalanceText.currency))
                }
                if !account.mergedKeys.isEmpty {
                    LabeledContent("Merged accounts", value: "\(account.mergedKeys.count)")
                }
                if account.isHidden {
                    LabeledContent("Hidden", value: "Yes")
                }
            }

            Section {
                Button {
                    sheet = .setBalance
                } label: {
                    Label(account.kind == .creditCard ? "Set available credit" : "Set balance", systemImage: "square.and.pencil")
                }
                if account.manualBalance != nil {
                    Button("Remove the balance you set", role: .destructive) {
                        do {
                            try TransactionEditor(context: context).clearManualBalance(account)
                        } catch {
                            errorText = error.localizedDescription
                        }
                    }
                }
                Button {
                    sheet = .merge
                } label: {
                    Label("Merge into another account…", systemImage: "arrow.triangle.merge")
                }
            } footer: {
                Text("Balances come from your bank SMS. Transactions without a balance in the SMS adjust the last known balance, shown as estimated.")
            }

            if !recent.isEmpty {
                Section("Recent transactions") {
                    ForEach(recent.prefix(25)) { transaction in
                        NavigationLink {
                            TransactionDetailView(transaction: transaction)
                        } label: {
                            TransactionRow(transaction: transaction)
                        }
                    }
                }
            }
        }
        .navigationTitle(account.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { sheet = .edit }
        }
    }

    @ViewBuilder
    private func creditCardRows(_ balance: AccountBalance) -> some View {
        if let limit = account.creditLimit {
            LabeledContent("Credit limit", value: AmountFormatter.string(limit, currency: BalanceText.currency))
            if let owed = balance.amountOwed {
                LabeledContent("Owed") {
                    Text(AmountFormatter.string(owed, currency: BalanceText.currency))
                        .foregroundStyle(owed > 0 ? Color.red : Color.primary)
                }
            }
            if let utilization = balance.utilization {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: utilization)
                        .tint(utilization > 0.8 ? .red : (utilization > 0.5 ? .orange : .green))
                    Text("\(utilization.formatted(.percent.precision(.fractionLength(0)))) of your limit used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Button("Add credit limit to see what you owe") { sheet = .edit }
        }
    }
}
