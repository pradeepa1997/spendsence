import SwiftData
import SwiftUI
import SpendCore

/// Add a manual (cash) transaction, or edit an existing one. Edits can be remembered as merchant rules.
struct TransactionFormView: View {
    enum Mode {
        /// New manual entry, optionally resolving an SMS the parser couldn't read.
        case add(linking: RawMessage?)
        case edit(SpendCore.Transaction)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Account.displayName)
    private var accounts: [Account]

    @State private var amountText: String
    @State private var type: TransactionType
    @State private var merchant: String
    @State private var categoryID: UUID?
    @State private var date: Date
    @State private var note: String
    @State private var currency: String
    /// Add mode only: nil = Cash.
    @State private var accountID: UUID?

    @State private var errorText: String?
    @State private var pendingRule: EditOutcome?
    @State private var showRememberDialog = false
    @FocusState private var amountFocused: Bool

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            _amountText = State(initialValue: "")
            _type = State(initialValue: .debit)
            _merchant = State(initialValue: "")
            _categoryID = State(initialValue: nil)
            _date = State(initialValue: .now)
            _note = State(initialValue: "")
            _currency = State(initialValue: "LKR")
        case .edit(let transaction):
            _amountText = State(initialValue: transaction.amount.plainString)
            _type = State(initialValue: transaction.type)
            _merchant = State(initialValue: transaction.merchant ?? "")
            _categoryID = State(initialValue: transaction.category?.id)
            _date = State(initialValue: transaction.occurredAt)
            _note = State(initialValue: transaction.note ?? "")
            _currency = State(initialValue: transaction.currency)
        }
    }

    var body: some View {
        Form {
            if case .add(let raw?) = mode {
                Section("SMS") {
                    Text(raw.body)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Text(currency)
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.title2.monospacedDigit())
                        .focused($amountFocused)
                }
                Picker("Type", selection: $type) {
                    ForEach(TransactionType.editable, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                TextField("Merchant or description", text: $merchant)
                CategoryPicker(selection: $categoryID)
                DatePicker("Date", selection: $date)
                if isAdding {
                    Picker("Account", selection: $accountID) {
                        Text(TransactionEditor.cashAccountName).tag(UUID?.none)
                        ForEach(accounts.filter { $0.bankName != TransactionEditor.cashAccountName }) { account in
                            Text(account.displayName).tag(Optional(account.id))
                        }
                    }
                }
            }

            Section("Note") {
                TextField("Optional", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }

            if case .edit(let transaction) = mode, let original = transaction.originalMerchant,
               original != merchant.trimmingCharacters(in: .whitespaces) {
                Section {
                    LabeledContent("Bank's merchant text", value: original)
                }
            }
        }
        .navigationTitle(isAdding ? "Add transaction" : "Edit transaction")
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
        .onAppear {
            if isAdding { amountFocused = true }
        }
        .confirmationDialog(
            rememberTitle,
            isPresented: $showRememberDialog,
            titleVisibility: .visible,
            presenting: pendingRule
        ) { outcome in
            Button("Remember for future messages") { remember(outcome, applyToPast: false) }
            Button("Remember and update past transactions") { remember(outcome, applyToPast: true) }
            Button("Just this one", role: .cancel) { dismiss() }
        } message: { outcome in
            Text(rememberMessage(for: outcome))
        }
        .errorAlert($errorText)
    }

    private var isAdding: Bool {
        if case .add = mode { return true }
        return false
    }

    private var editor: TransactionEditor { TransactionEditor(context: context) }

    private func save() {
        guard let amount = AmountParser.parse(amountText) else {
            errorText = EditorError.invalidAmount.localizedDescription
            return
        }
        let draft = TransactionDraft(
            amount: amount,
            currency: currency,
            type: type,
            merchant: merchant,
            categoryID: categoryID,
            occurredAt: date,
            note: note,
            accountID: accountID
        )
        do {
            switch mode {
            case .add(let raw):
                try editor.addManual(draft, linking: raw)
                dismiss()
            case .edit(let transaction):
                let outcome = try editor.update(transaction, with: draft)
                if outcome.canRemember {
                    pendingRule = outcome
                    showRememberDialog = true
                } else {
                    dismiss()
                }
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func remember(_ outcome: EditOutcome, applyToPast: Bool) {
        guard case .edit(let transaction) = mode else {
            dismiss()
            return
        }
        do {
            try editor.remember(
                from: transaction,
                rename: outcome.merchantRenamed,
                category: outcome.categoryChanged,
                applyToPast: applyToPast
            )
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private var rememberTitle: String {
        "Remember this for “\(pendingRule?.merchantKey ?? "")”?"
    }

    private func rememberMessage(for outcome: EditOutcome) -> String {
        var parts: [String] = []
        if outcome.merchantRenamed {
            parts.append("show it as “\(merchant.trimmingCharacters(in: .whitespaces))”")
        }
        if outcome.categoryChanged, case .edit(let transaction) = mode, let name = transaction.category?.name {
            parts.append("file it under \(name)")
        }
        return "Future SMS from this merchant will " + parts.joined(separator: " and ") + "."
    }
}
