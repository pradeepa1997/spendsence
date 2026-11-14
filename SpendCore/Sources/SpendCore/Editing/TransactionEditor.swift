import Foundation
import SwiftData

/// Values for creating or editing a transaction by hand.
public struct TransactionDraft: Sendable, Equatable {
    public var amount: Decimal
    public var currency: String
    public var type: TransactionType
    public var merchant: String?
    /// Takes precedence over `categoryName`. Both nil → categorised automatically.
    public var categoryID: UUID?
    /// Case-insensitive category name (Siri). Ignored if `categoryID` is set.
    public var categoryName: String?
    public var occurredAt: Date
    public var note: String?
    /// For new manual entries: the account to use; nil means the Cash account. Ignored when editing.
    public var accountID: UUID?

    public init(
        amount: Decimal,
        currency: String = "LKR",
        type: TransactionType = .debit,
        merchant: String? = nil,
        categoryID: UUID? = nil,
        categoryName: String? = nil,
        occurredAt: Date = .now,
        note: String? = nil,
        accountID: UUID? = nil
    ) {
        self.amount = amount
        self.currency = currency
        self.type = type
        self.merchant = merchant
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.occurredAt = occurredAt
        self.note = note
        self.accountID = accountID
    }
}

/// What changed in an edit, so the UI can offer to remember it as a merchant rule.
public struct EditOutcome: Sendable, Equatable {
    /// Key of the merchant as originally parsed: the pattern a rule would use.
    public let merchantKey: String?
    public let merchantRenamed: Bool
    public let categoryChanged: Bool

    public var canRemember: Bool {
        merchantKey != nil && (merchantRenamed || categoryChanged)
    }
}

public enum EditorError: Error, LocalizedError, Equatable {
    case invalidAmount
    case emptyName
    case systemCategoryCannotBeDeleted
    case invalidCreditLimit
    case cannotMergeIntoItself

    public var errorDescription: String? {
        switch self {
        case .invalidAmount: "Enter an amount greater than 0."
        case .emptyName: "Enter a name."
        case .systemCategoryCannotBeDeleted: "Built-in categories can be renamed but not deleted."
        case .invalidCreditLimit: "The credit limit must be greater than 0."
        case .cannotMergeIntoItself: "Choose a different account to merge into."
        }
    }
}

/// Every user-initiated change to transactions, categories and rules. Each method saves (or rolls back on failure).
///
/// The UI runs it on the view's `modelContext` so lists refresh immediately; `TransactionStore` runs it on its actor
/// context for Siri intents. Never mutate models directly from views.
public struct TransactionEditor {
    public static let cashAccountName = "Cash"

    public let context: ModelContext
    /// A `ModelContext` doesn't keep its container alive; holding it here means an editor (and its context)
    /// stays valid however the caller stores the container.
    private let container: ModelContainer

    public init(context: ModelContext) {
        self.context = context
        self.container = context.container
    }

    // MARK: Transactions

    /// Creates a manual (e.g. cash) transaction. Optionally links an SMS the parser couldn't read.
    @discardableResult
    public func addManual(_ draft: TransactionDraft, linking raw: RawMessage? = nil) throws -> Transaction {
        guard draft.amount > 0, draft.amount <= AmountParser.maximum else { throw EditorError.invalidAmount }
        let merchant = Self.clean(draft.merchant)
        let account = try account(for: draft.accountID)

        let transaction = Transaction(
            amount: draft.amount,
            currency: draft.currency,
            type: draft.type,
            merchant: merchant,
            occurredAt: draft.occurredAt,
            confidence: 1,
            source: .manual,
            note: Self.clean(draft.note),
            isUserEdited: true
        )
        context.insert(transaction)
        transaction.account = account
        transaction.isReviewed = true

        if let chosen = try chosenCategory(for: draft) {
            transaction.category = chosen
            transaction.categoryIsManual = true
        } else {
            transaction.category = try CategoryService.resolve(merchant: merchant, type: draft.type, in: context).category
        }

        if let raw {
            transaction.rawMessage = raw
            raw.status = .parsed
            raw.failureReason = "Added manually"
        }
        try save()
        return transaction
    }

    /// Applies an edit. Marks the transaction as user-edited and reviewed.
    @discardableResult
    public func update(_ transaction: Transaction, with draft: TransactionDraft) throws -> EditOutcome {
        guard draft.amount > 0, draft.amount <= AmountParser.maximum else { throw EditorError.invalidAmount }
        let previousMerchant = transaction.merchant
        let previousCategoryID = transaction.category?.id
        if transaction.originalMerchant == nil { transaction.originalMerchant = previousMerchant }

        transaction.amount = draft.amount
        transaction.currency = draft.currency
        transaction.type = draft.type
        transaction.merchant = Self.clean(draft.merchant)
        transaction.occurredAt = draft.occurredAt
        transaction.note = Self.clean(draft.note)
        transaction.category = try chosenCategory(for: draft)
        transaction.isUserEdited = true
        transaction.isReviewed = true

        let categoryChanged = transaction.category?.id != previousCategoryID
        if categoryChanged { transaction.categoryIsManual = transaction.category != nil }
        try save()

        return EditOutcome(
            merchantKey: MerchantKey.make(transaction.originalMerchant),
            merchantRenamed: transaction.merchant != previousMerchant && transaction.merchant != nil,
            categoryChanged: categoryChanged && transaction.category != nil
        )
    }

    /// Quick category change (e.g. from a picker), without touching other fields.
    @discardableResult
    public func setCategory(_ category: TransactionCategory?, for transaction: Transaction) throws -> EditOutcome {
        let changed = transaction.category?.id != category?.id
        transaction.category = category
        if changed { transaction.categoryIsManual = category != nil }
        transaction.isReviewed = true
        try save()
        return EditOutcome(
            merchantKey: MerchantKey.make(transaction.originalMerchant ?? transaction.merchant),
            merchantRenamed: false,
            categoryChanged: changed && category != nil
        )
    }

    /// Turns an edit into a merchant rule for future SMS, optionally applying it to past transactions from the same
    /// merchant (past transactions whose category the user picked by hand keep it). Returns how many past
    /// transactions changed.
    @discardableResult
    public func remember(from transaction: Transaction, rename: Bool, category: Bool, applyToPast: Bool) throws -> Int {
        guard rename || category,
              let pattern = MerchantKey.make(transaction.originalMerchant ?? transaction.merchant)
        else { return 0 }

        let existing = try context.fetch(FetchDescriptor<MerchantRule>(predicate: #Predicate { $0.pattern == pattern }))
        let rule: MerchantRule
        if let first = existing.first {
            rule = first
        } else {
            rule = MerchantRule(pattern: pattern)
            context.insert(rule)
        }
        if rename { rule.renameTo = transaction.merchant }
        if category { rule.category = transaction.category }

        var updated = 0
        if applyToPast {
            for other in try context.fetch(FetchDescriptor<Transaction>()) where other.id != transaction.id {
                guard let key = MerchantKey.make(other.originalMerchant ?? other.merchant),
                      MerchantKey.matches(key, pattern: pattern)
                else { continue }
                var changed = false
                if rename, let newName = transaction.merchant, other.merchant != newName {
                    if other.originalMerchant == nil { other.originalMerchant = other.merchant }
                    other.merchant = newName
                    changed = true
                }
                if category, !other.categoryIsManual, other.category?.id != transaction.category?.id {
                    other.category = transaction.category
                    changed = true
                }
                if changed { updated += 1 }
            }
        }
        try save()
        return updated
    }

    /// Removes the transaction from the review queue without changing it.
    public func approve(_ transaction: Transaction) throws {
        transaction.isReviewed = true
        try save()
    }

    /// Deletes the transaction and marks its SMS as ignored (e.g. a parsed OTP or a balance notice).
    public func markNotATransaction(_ transaction: Transaction) throws {
        try remove(transaction, reason: "Marked as not a transaction")
    }

    public func delete(_ transaction: Transaction) throws {
        try remove(transaction, reason: "Transaction deleted by user")
    }

    /// Drops an unreadable SMS from the review queue.
    public func dismiss(_ raw: RawMessage) throws {
        raw.status = .ignored
        raw.failureReason = "Dismissed by user"
        try save()
    }

    // MARK: Categories & rules

    @discardableResult
    public func addCategory(name: String, symbol: String, colorHex: String) throws -> TransactionCategory {
        guard let name = Self.clean(name) else { throw EditorError.emptyName }
        let categories = try CategoryService.ensureDefaultCategories(in: context)
        let category = TransactionCategory(
            name: name, symbol: symbol, colorHex: colorHex,
            sortOrder: (categories.map(\.sortOrder).max() ?? 0) + 1
        )
        context.insert(category)
        try save()
        return category
    }

    public func updateCategory(_ category: TransactionCategory, name: String, symbol: String, colorHex: String) throws {
        guard let name = Self.clean(name) else { throw EditorError.emptyName }
        category.name = name
        category.symbol = symbol
        category.colorHex = colorHex
        try save()
    }

    /// Deletes a user category. Its transactions move to Other; rules that only set this category are deleted.
    public func deleteCategory(_ category: TransactionCategory) throws {
        guard !category.isSystem else { throw EditorError.systemCategoryCannotBeDeleted }
        let other = try CategoryService.ensureDefaultCategories(in: context)
            .first { $0.systemKey == DefaultCategories.other }
        for transaction in category.transactions {
            transaction.category = other
            transaction.categoryIsManual = false
        }
        for rule in category.rules {
            if rule.renameTo == nil {
                context.delete(rule)
            } else {
                rule.category = nil
            }
        }
        context.delete(category)
        try save()
    }

    public func deleteRule(_ rule: MerchantRule) throws {
        context.delete(rule)
        try save()
    }

    // MARK: Accounts

    /// Edits an account. Choosing a kind stops SMS detection from changing it.
    public func updateAccount(
        _ account: Account,
        name: String,
        kind: AccountKind,
        creditLimit: Decimal?,
        lowBalanceThreshold: Decimal?,
        isHidden: Bool
    ) throws {
        guard let name = Self.clean(name) else { throw EditorError.emptyName }
        if let creditLimit, creditLimit <= 0 { throw EditorError.invalidCreditLimit }
        account.displayName = name
        if kind != account.kind {
            account.kind = kind
            account.kindIsManual = true
        }
        account.creditLimit = kind == .creditCard ? creditLimit : nil
        account.lowBalanceThreshold = lowBalanceThreshold
        account.isHidden = isHidden
        try save()
    }

    /// "Set balance": the balance (or available credit) at `date`. Later transactions adjust it as usual.
    public func setBalance(_ account: Account, to amount: Decimal, at date: Date = .now) throws {
        account.manualBalance = amount
        account.manualBalanceAt = date
        try save()
    }

    public func clearManualBalance(_ account: Account) throws {
        account.manualBalance = nil
        account.manualBalanceAt = nil
        try save()
    }

    /// Moves `source`'s transactions into `target` and deletes `source`. Its (bank, ending) is kept as an alias on
    /// `target`, so future SMS for it land in `target`.
    public func merge(_ source: Account, into target: Account) throws {
        guard source.id != target.id else { throw EditorError.cannotMergeIntoItself }
        for transaction in source.transactions {
            transaction.account = target
        }
        var keys = target.mergedKeys
        for key in [Account.aliasKey(bankName: source.bankName, last4: source.last4)] + source.mergedKeys
        where !keys.contains(key) {
            keys.append(key)
        }
        target.mergedKeys = keys
        if target.kind == .unknown && !target.kindIsManual {
            target.kind = source.kind
        }
        if target.creditLimit == nil { target.creditLimit = source.creditLimit }
        if target.lowBalanceThreshold == nil { target.lowBalanceThreshold = source.lowBalanceThreshold }
        if let sourceAt = source.manualBalanceAt, sourceAt > (target.manualBalanceAt ?? .distantPast) {
            target.manualBalance = source.manualBalance
            target.manualBalanceAt = sourceAt
        }
        context.delete(source)
        try save()
    }

    /// Dev convenience: wipes everything, then re-seeds the default categories.
    public func deleteAllData() throws {
        for transaction in try context.fetch(FetchDescriptor<Transaction>()) { context.delete(transaction) }
        for raw in try context.fetch(FetchDescriptor<RawMessage>()) { context.delete(raw) }
        for account in try context.fetch(FetchDescriptor<Account>()) { context.delete(account) }
        for rule in try context.fetch(FetchDescriptor<MerchantRule>()) { context.delete(rule) }
        for category in try context.fetch(FetchDescriptor<TransactionCategory>()) { context.delete(category) }
        try save()
        try CategoryService.ensureDefaultCategories(in: context)
        try save()
    }

    // MARK: Private

    private func remove(_ transaction: Transaction, reason: String) throws {
        if let raw = transaction.rawMessage {
            raw.status = .ignored
            raw.failureReason = reason
        }
        context.delete(transaction)
        try save()
    }

    private func chosenCategory(for draft: TransactionDraft) throws -> TransactionCategory? {
        if let id = draft.categoryID {
            return try CategoryService.category(withID: id, in: context)
        }
        if let name = draft.categoryName {
            return try CategoryService.category(named: name, in: context)
        }
        return nil
    }

    /// The chosen account, or the single Cash account (created on first use).
    private func account(for id: UUID?) throws -> Account {
        if let id, let account = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })).first {
            return account
        }
        let cashName = Self.cashAccountName
        let cashAccounts = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.bankName == cashName }))
        if let cash = cashAccounts.first(where: { $0.last4 == nil }) {
            return cash
        }
        let cash = Account(bankName: cashName, last4: nil, displayName: cashName, kind: .cash)
        context.insert(cash)
        return cash
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
