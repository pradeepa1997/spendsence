import SwiftData
import SwiftUI
import SpendCore

struct AccountsView: View {
    @Query(sort: \Account.displayName)
    private var accounts: [Account]

    @State private var showHidden = false

    var body: some View {
        let visible = accounts.filter { !$0.isHidden }
        let hidden = accounts.filter(\.isHidden)

        Group {
            if accounts.isEmpty {
                ContentUnavailableView(
                    "No accounts yet",
                    systemImage: "building.columns",
                    description: Text("Accounts and cards are created automatically from your bank SMS. Cash appears after your first manual entry.")
                )
            } else {
                List {
                    Section {
                        AccountsTotalsView(overview: AccountsOverview.make(visible.map(\.balance)))
                    }
                    accountSection("Bank accounts & debit cards", visible.filter { $0.kind == .bankAccount || $0.kind == .debitCard })
                    accountSection("Credit cards", visible.filter { $0.kind == .creditCard })
                    accountSection("Cash", visible.filter { $0.kind == .cash })
                    accountSection("Other", visible.filter { $0.kind == .unknown })
                    if !hidden.isEmpty {
                        Section {
                            DisclosureGroup("Hidden (\(hidden.count))", isExpanded: $showHidden) {
                                ForEach(hidden) { account in
                                    accountLink(account)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Accounts")
    }

    @ViewBuilder
    private func accountSection(_ title: String, _ items: [Account]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { account in
                    accountLink(account)
                }
            }
        }
    }

    private func accountLink(_ account: Account) -> some View {
        NavigationLink {
            AccountDetailView(account: account)
        } label: {
            AccountRow(account: account)
        }
    }
}

struct AccountsTotalsView: View {
    let overview: AccountsOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                total("In accounts", value: overview.moneyInAccounts, color: .primary)
                Spacer()
                total("Owed on cards", value: overview.owedOnCards, color: overview.owedOnCards > 0 ? .red : .primary)
            }
            if overview.cardsWithoutLimit > 0 {
                Text(overview.cardsWithoutLimit == 1
                     ? "Set a credit limit on 1 card to include what you owe on it."
                     : "Set credit limits on \(overview.cardsWithoutLimit) cards to include what you owe on them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if overview.unknownBalanceCount > 0 {
                Text("\(overview.unknownBalanceCount) account(s) have no balance yet. Open one and use Set balance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func total(_ title: String, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AmountFormatter.string(value, currency: BalanceText.currency))
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

struct AccountRow: View {
    let account: Account

    var body: some View {
        let balance = account.balance
        HStack(spacing: 12) {
            AccountIcon(kind: account.kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(BalanceText.caption(balance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(BalanceText.primary(balance))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(balance.isBelow(account.lowBalanceThreshold) ? Color.orange : Color.primary)
                if let owed = balance.amountOwed {
                    Text("Owed \(AmountFormatter.string(owed, currency: BalanceText.currency))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
