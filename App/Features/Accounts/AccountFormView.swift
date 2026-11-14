import SwiftData
import SwiftUI
import SpendCore

/// Edit name, type, credit limit, low-balance alert and visibility.
struct AccountFormView: View {
    let account: Account

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var kind: AccountKind
    @State private var creditLimitText: String
    @State private var thresholdText: String
    @State private var isHidden: Bool
    @State private var errorText: String?

    init(account: Account) {
        self.account = account
        _name = State(initialValue: account.displayName)
        _kind = State(initialValue: account.kind == .unknown ? .bankAccount : account.kind)
        _creditLimitText = State(initialValue: account.creditLimit?.plainString ?? "")
        _thresholdText = State(initialValue: account.lowBalanceThreshold?.plainString ?? "")
        _isHidden = State(initialValue: account.isHidden)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                Picker("Type", selection: $kind) {
                    ForEach(AccountKind.editable, id: \.self) { kind in
                        Label(kind.label, systemImage: kind.symbol).tag(kind)
                    }
                }
            } footer: {
                Text("\(account.bankName)\(account.last4.map { " ••\($0)" } ?? ""). Choosing a type stops SMS detection from changing it.")
            }

            if kind == .creditCard {
                Section {
                    amountField("Credit limit", text: $creditLimitText)
                } footer: {
                    Text("With a limit, SpendSense shows what you owe: limit − available credit from the SMS.")
                }
            }

            Section {
                amountField(kind == .creditCard ? "Alert below (available credit)" : "Alert below", text: $thresholdText)
            } header: {
                Text("Low-balance alert")
            } footer: {
                Text("Shown on the Dashboard when the balance drops below this. Leave empty for no alert.")
            }

            Section {
                Toggle("Hide from Accounts and totals", isOn: $isHidden)
            }
        }
        .navigationTitle("Edit account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .errorAlert($errorText)
    }

    private func amountField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("LKR", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160)
        }
    }

    private func save() {
        let limit = AmountInput.parse(creditLimitText)
        let threshold = AmountInput.parse(thresholdText)
        if !creditLimitText.trimmingCharacters(in: .whitespaces).isEmpty, limit == nil, kind == .creditCard {
            errorText = "Enter the credit limit as a number."
            return
        }
        if !thresholdText.trimmingCharacters(in: .whitespaces).isEmpty, threshold == nil {
            errorText = "Enter the alert amount as a number."
            return
        }
        do {
            try TransactionEditor(context: context).updateAccount(
                account, name: name, kind: kind, creditLimit: limit, lowBalanceThreshold: threshold, isHidden: isHidden
            )
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// "Set balance": an opening balance or a correction.
struct SetBalanceView: View {
    let account: Account

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var date = Date.now
    @State private var errorText: String?

    init(account: Account) {
        self.account = account
        _amountText = State(initialValue: account.balance.value?.plainString ?? "")
    }

    private var isCredit: Bool { account.kind == .creditCard }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(BalanceText.currency).foregroundStyle(.secondary)
                    TextField("0.00", text: $amountText)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.title2.monospacedDigit())
                }
                DatePicker("As of", selection: $date)
            } footer: {
                Text(isCredit
                     ? "Enter the available credit shown by your bank. Transactions after this date adjust it."
                     : "Enter the balance shown by your bank (use − for an overdraft). Transactions after this date adjust it; a newer balance in an SMS replaces it.")
            }
        }
        .navigationTitle(isCredit ? "Set available credit" : "Set balance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(amountText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .errorAlert($errorText)
    }

    private func save() {
        guard let amount = AmountInput.parse(amountText, allowNegative: !isCredit) else {
            errorText = "Enter the amount as a number."
            return
        }
        do {
            try TransactionEditor(context: context).setBalance(account, to: amount, at: date)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Merge this account into another (e.g. a card number and its account number for the same account).
struct MergeAccountView: View {
    let account: Account
    /// Called right after a successful merge, before this sheet closes (the source account no longer exists).
    let onMerged: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Account.displayName)
    private var accounts: [Account]

    @State private var targetID: UUID?
    @State private var confirm = false
    @State private var errorText: String?

    /// Copied at init so the view never reads the account after it has been merged away.
    private let sourceID: UUID
    private let sourceName: String

    init(account: Account, onMerged: @escaping () -> Void) {
        self.account = account
        self.onMerged = onMerged
        self.sourceID = account.id
        self.sourceName = account.displayName
    }

    var body: some View {
        let candidates = accounts.filter { $0.id != sourceID }
        Form {
            Section {
                Picker("Merge into", selection: $targetID) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(candidates) { candidate in
                        Text(candidate.displayName).tag(Optional(candidate.id))
                    }
                }
            } footer: {
                Text("All of “\(sourceName)”'s transactions move to the chosen account, and future SMS for it go there too. “\(sourceName)” is then removed.")
            }
        }
        .navigationTitle("Merge account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Merge") { confirm = true }
                    .disabled(targetID == nil)
            }
        }
        .confirmationDialog("Merge “\(sourceName)”?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Merge", role: .destructive) { merge(into: candidates) }
        } message: {
            Text("This can't be undone.")
        }
        .errorAlert($errorText)
    }

    private func merge(into candidates: [Account]) {
        guard let target = candidates.first(where: { $0.id == targetID }) else { return }
        do {
            try TransactionEditor(context: context).merge(account, into: target)
            onMerged() // same main-actor turn as the merge, so nothing renders the deleted account in between
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
