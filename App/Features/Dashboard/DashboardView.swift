import Charts
import SwiftData
import SwiftUI
import SpendCore

struct DashboardView: View {
    @Query(sort: \SpendCore.Transaction.occurredAt, order: .reverse)
    private var transactions: [SpendCore.Transaction]

    @Query(sort: \Account.displayName)
    private var accounts: [Account]

    @Query(sort: \TransactionCategory.sortOrder)
    private var categories: [TransactionCategory]

    @State private var month = SpendingSummary.month(containing: .now)
    @State private var showAdd = false

    var body: some View {
        let summary = SpendingSummary.make(facts: transactions.map { TransactionFact($0) }, interval: month)
        let awaitingReview = transactions.filter(\.isAwaitingReview).count

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LiveAutomationHealthBanner(suppressNeverReceived: transactions.isEmpty)
                monthPicker
                TotalsCard(summary: summary)

                let budgets = BudgetCalculator.statuses(summary: summary, budgets: BudgetsView.inputs(from: categories))
                if !budgets.isEmpty {
                    NavigationLink {
                        BudgetsView()
                    } label: {
                        BudgetsCard(statuses: budgets)
                    }
                    .buttonStyle(.plain)
                }

                let visibleAccounts = accounts.filter { !$0.isHidden }
                if !visibleAccounts.isEmpty {
                    NavigationLink {
                        AccountsView()
                    } label: {
                        AccountsCard(accounts: visibleAccounts)
                    }
                    .buttonStyle(.plain)
                }

                if awaitingReview > 0 {
                    NavigationLink {
                        ReviewQueueView()
                    } label: {
                        ReviewChip(count: awaitingReview)
                    }
                    .buttonStyle(.plain)
                }

                if summary.transactionCount == 0 {
                    ContentUnavailableView(
                        "Nothing this month",
                        systemImage: "chart.pie",
                        description: Text("Bank SMS and manual entries for this month will appear here.")
                    )
                } else {
                    if !summary.byCategory.isEmpty {
                        CategoryBreakdownCard(summary: summary)
                    }
                    DailySpendCard(summary: summary)
                    if !summary.topMerchants.isEmpty {
                        TopMerchantsCard(summary: summary)
                    }
                }

                if summary.otherCurrencyCount > 0 {
                    Text("\(summary.otherCurrencyCount) transaction(s) in other currencies aren't included in these totals.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dashboard")
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
    }

    private var monthPicker: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(month.start, format: .dateTime.month(.wide).year())
                .font(.headline)
            Spacer()
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(month.end > .now)
        }
        .buttonStyle(.bordered)
    }

    private func shiftMonth(by months: Int) {
        guard let date = Calendar.current.date(byAdding: .month, value: months, to: month.start) else { return }
        month = SpendingSummary.month(containing: date)
    }
}

// MARK: - Cards

private struct Card<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct TotalsCard: View {
    let summary: SpendingSummary

    var body: some View {
        Card {
            Text("Spent")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(AmountFormatter.string(summary.totalSpent, currency: summary.currency))
                .font(.largeTitle.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            HStack {
                stat("Income", value: summary.totalIncome, color: .green)
                Spacer()
                stat("Net", value: summary.net, color: summary.net >= 0 ? .green : .red)
            }
        }
    }

    private func stat(_ title: String, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AmountFormatter.string(value, currency: summary.currency))
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
        }
    }
}

private struct AccountsCard: View {
    let accounts: [Account]

    var body: some View {
        let balances = accounts.map(\.balance)
        let overview = AccountsOverview.make(balances)
        let lowAccounts = accounts.filter { $0.balance.isBelow($0.lowBalanceThreshold) }

        Card {
            HStack {
                Text("Accounts").font(.headline)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            HStack(alignment: .top) {
                figure("In accounts", value: overview.moneyInAccounts, color: .primary)
                Spacer()
                figure("Owed on cards", value: overview.owedOnCards, color: overview.owedOnCards > 0 ? .red : .primary)
            }
            ForEach(lowAccounts) { account in
                Label("\(account.displayName) is low: \(BalanceText.primary(account.balance))",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func figure(_ title: String, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AmountFormatter.string(value, currency: BalanceText.currency))
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
        }
    }
}

private struct BudgetsCard: View {
    let statuses: [BudgetStatus]

    var body: some View {
        Card {
            HStack {
                Text("Budgets").font(.headline)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            ForEach(statuses.prefix(4)) { status in
                BudgetRow(status: status)
            }
            if statuses.count > 4 {
                Text("+\(statuses.count - 4) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ReviewChip: View {
    let count: Int

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text(count == 1 ? "1 transaction to review" : "\(count) transactions to review")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CategoryBreakdownCard: View {
    let summary: SpendingSummary

    var body: some View {
        Card("By category") {
            Chart(summary.byCategory) { item in
                SectorMark(
                    angle: .value("Amount", item.amount.doubleValue),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(Color(hex: item.colorHex))
            }
            .frame(height: 200)

            ForEach(summary.byCategory) { item in
                HStack(spacing: 10) {
                    CategoryIconView(symbol: item.symbol, colorHex: item.colorHex, size: 26)
                    Text(item.name)
                    Spacer()
                    Text(share(of: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(AmountFormatter.string(item.amount, currency: summary.currency))
                        .font(.subheadline.monospacedDigit())
                }
            }
        }
    }

    private func share(of item: SpendingSummary.CategoryTotal) -> String {
        guard summary.totalSpent > 0 else { return "" }
        return (item.amount / summary.totalSpent).doubleValue.formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct DailySpendCard: View {
    let summary: SpendingSummary

    var body: some View {
        Card("Daily spending") {
            Chart(summary.byDay) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Spent", max(day.amount.doubleValue, 0))
                )
                .foregroundStyle(Color.accentColor.gradient)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .frame(height: 160)
        }
    }
}

private struct TopMerchantsCard: View {
    let summary: SpendingSummary

    var body: some View {
        Card("Top merchants") {
            ForEach(summary.topMerchants) { merchant in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(merchant.name)
                            .lineLimit(1)
                        Text(merchant.count == 1 ? "1 transaction" : "\(merchant.count) transactions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(AmountFormatter.string(merchant.amount, currency: summary.currency))
                        .font(.subheadline.monospacedDigit())
                }
            }
        }
    }
}
