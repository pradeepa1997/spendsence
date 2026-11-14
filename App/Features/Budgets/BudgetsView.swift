import SwiftData
import SwiftUI
import SpendCore

/// This month's budgets with progress, plus categories without one.
struct BudgetsView: View {
    @Query(sort: \TransactionCategory.sortOrder)
    private var categories: [TransactionCategory]

    @Query(sort: \SpendCore.Transaction.occurredAt, order: .reverse)
    private var transactions: [SpendCore.Transaction]

    @State private var editing: TransactionCategory?

    var body: some View {
        let month = SpendingSummary.month(containing: .now)
        let summary = SpendingSummary.make(facts: transactions.map { TransactionFact($0) }, interval: month)
        let statuses = BudgetCalculator.statuses(summary: summary, budgets: Self.inputs(from: categories))
        let unbudgeted = categories.filter { category in
            category.monthlyBudget == nil
                && !category.excludedFromSpending
                && category.systemKey != DefaultCategories.income
        }

        List {
            if statuses.isEmpty {
                Section {
                    Text("Set a monthly budget on a category to track it here. You'll get a notification at 80% and 100%.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(statuses) { status in
                        Button {
                            editing = categories.first { $0.id == status.categoryID }
                        } label: {
                            BudgetRow(status: status)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(month.start.formatted(.dateTime.month(.wide).year()))
                }
            }

            if !unbudgeted.isEmpty {
                Section("Add a budget") {
                    ForEach(unbudgeted) { category in
                        Button {
                            editing = category
                        } label: {
                            HStack(spacing: 12) {
                                CategoryIcon(category: category, size: 28)
                                Text(category.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Budgets")
        .sheet(item: $editing) { category in
            NavigationStack {
                BudgetEditorView(category: category)
            }
            .presentationDetents([.medium])
        }
    }

    static func inputs(from categories: [TransactionCategory]) -> [BudgetInput] {
        categories.compactMap { category in
            guard let budget = category.monthlyBudget else { return nil }
            return BudgetInput(
                categoryID: category.id, name: category.name, symbol: category.symbol,
                colorHex: category.colorHex, budget: budget
            )
        }
    }
}

struct BudgetRow: View {
    let status: BudgetStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                CategoryIconView(symbol: status.symbol, colorHex: status.colorHex, size: 28)
                Text(status.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(AmountFormatter.compact(status.spent, currency: "LKR")) / \(AmountFormatter.compact(status.budget, currency: "LKR"))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(status.fraction, 1))
                .tint(status.level.color)
            Text(remainingText)
                .font(.caption)
                .foregroundStyle(status.level == .over ? Color.red : Color.secondary)
        }
        .padding(.vertical, 2)
    }

    private var remainingText: String {
        let remaining = status.remaining
        if remaining >= 0 {
            return "\(AmountFormatter.string(remaining, currency: "LKR")) left"
        }
        return "\(AmountFormatter.string(-remaining, currency: "LKR")) over budget"
    }
}

extension BudgetStatus.Level {
    var color: Color {
        switch self {
        case .ok: .green
        case .warning: .orange
        case .over: .red
        }
    }
}

struct BudgetEditorView: View {
    let category: TransactionCategory

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var errorText: String?

    init(category: TransactionCategory) {
        self.category = category
        _amountText = State(initialValue: category.monthlyBudget?.plainString ?? "")
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    CategoryIcon(category: category, size: 28)
                    Text(category.name)
                }
                HStack {
                    Text("LKR").foregroundStyle(.secondary)
                    TextField("Monthly budget", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.title3.monospacedDigit())
                }
            } footer: {
                Text("You'll get a notification when spending in \(category.name) reaches 80% and 100% of this in a month.")
            }
            if category.monthlyBudget != nil {
                Section {
                    Button("Remove budget", role: .destructive) { save(nil) }
                }
            }
        }
        .navigationTitle("Monthly budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let amount = AmountInput.parse(amountText) else {
                        errorText = EditorError.invalidBudget.localizedDescription
                        return
                    }
                    save(amount)
                }
                .disabled(amountText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .errorAlert($errorText)
    }

    private func save(_ amount: Decimal?) {
        do {
            try TransactionEditor(context: context).setBudget(category, to: amount)
            AppEvents.dataChanged()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
