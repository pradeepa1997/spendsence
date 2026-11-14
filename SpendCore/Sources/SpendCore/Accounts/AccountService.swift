import Foundation
import SwiftData

/// Account matching and balance timelines against a `ModelContext`. Callers save.
public enum AccountService {
    /// Finds the account an SMS belongs to, or creates it.
    ///
    /// Order: exact (bank, ending) → same bank with a compatible ending (`95` ↔ `7795`; the account keeps the longest
    /// ending) → a merge alias. A detected kind refines the account's kind unless the user set it.
    public static func upsert(
        bankName: String,
        last4: String?,
        detectedKind: AccountKind? = nil,
        in context: ModelContext
    ) throws -> Account {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let account: Account
        if let exact = accounts.first(where: { $0.bankName == bankName && $0.last4 == last4 }) {
            account = exact
        } else if let compatible = accounts.first(where: {
            $0.bankName == bankName && IngestionRules.sameAccount($0.last4, last4)
        }) {
            upgradeEnding(of: compatible, to: last4)
            account = compatible
        } else if let aliased = accounts.first(where: { $0.matches(bankName: bankName, last4: last4) }) {
            account = aliased
        } else {
            account = Account(bankName: bankName, last4: last4)
            context.insert(account)
        }
        if !account.kindIsManual {
            account.kind = account.kind.refined(with: detectedKind)
        }
        return account
    }

    /// One-time fix-ups for accounts created before Phase 2.5: the Cash wallet gets the `cash` kind.
    public static func prepare(in context: ModelContext) throws {
        let cashName = TransactionEditor.cashAccountName
        let cash = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.bankName == cashName }))
        for account in cash where account.last4 == nil && account.kind == .unknown {
            account.kind = .cash
        }
    }

    /// The account's timeline: its transactions plus the user's latest "Set balance".
    /// Transactions in another currency still reset to their reported balance but don't adjust it (no conversion).
    public static func events(for account: Account, currency: String = "LKR") -> [BalanceEvent] {
        var events: [BalanceEvent] = account.transactions.map { transaction in
            let effect: Decimal = transaction.currency == currency
                ? BalanceEvent.effect(of: transaction.type, amount: transaction.amount)
                : 0
            return BalanceEvent(
                date: transaction.occurredAt,
                sequence: transaction.createdAt,
                effect: effect,
                reportedBalance: transaction.balanceAfter
            )
        }
        if let manual = account.manualBalance, let at = account.manualBalanceAt {
            events.append(BalanceEvent(date: at, effect: 0, reportedBalance: manual, isManual: true))
        }
        return events
    }

    private static func upgradeEnding(of account: Account, to last4: String?) {
        guard let last4, last4.count > (account.last4?.count ?? 0) else { return }
        let hadDefaultName = account.displayName
            == Account.defaultDisplayName(bankName: account.bankName, last4: account.last4)
        account.last4 = last4
        if hadDefaultName {
            account.displayName = Account.defaultDisplayName(bankName: account.bankName, last4: last4)
        }
    }
}

extension Account {
    /// Current balance (or available credit) worked out from SMS-reported balances, transactions and "Set balance".
    public var balance: AccountBalance {
        BalanceCalculator.balance(kind: kind, events: AccountService.events(for: self), creditLimit: creditLimit)
    }
}
