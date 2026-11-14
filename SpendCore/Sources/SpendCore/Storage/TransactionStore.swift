import Foundation
import SwiftData

public enum StoreError: Error, LocalizedError, Sendable {
    case rawMessageNotFound

    public var errorDescription: String? {
        switch self {
        case .rawMessageNotFound: "Raw message not found in store"
        }
    }
}

/// Rules shared by dedup and account resolution.
enum IngestionRules {
    /// Same amount + same account within this window (either side) counts as a duplicate.
    static let duplicateWindow: TimeInterval = 3 * 60

    /// Template bank name, else the SMS sender ID, else a generic bucket.
    static func bankName(for parsed: ParsedTransaction, sender: String?) -> String {
        if let bank = parsed.bankName?.trimmingCharacters(in: .whitespaces), !bank.isEmpty { return bank }
        if let sender = sender?.trimmingCharacters(in: .whitespaces), !sender.isEmpty { return sender }
        return "Unknown Bank"
    }

    /// Whether two account endings refer to the same account. Some banks mask all but the last 2 digits
    /// (HNB `11202XXXXX95`) while their card alerts show 4 (`1120***7795`), so a 2–3 digit ending matches a
    /// longer one that ends with it. Both nil also matches (the "<bank> (unknown)" account).
    static func sameAccount(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (a?, b?):
            if a == b { return true }
            let (shorter, longer) = a.count <= b.count ? (a, b) : (b, a)
            return shorter.count >= 2 && longer.hasSuffix(shorter)
        default:
            return false
        }
    }

    /// Statuses whose body hash blocks an identical later message.
    static func blocksIdenticalBody(_ status: MessageStatus) -> Bool {
        switch status {
        case .parsed, .needsReview, .duplicate: true
        case .pending, .ignored, .failed: false
        }
    }
}

/// All SwiftData writes from ingestion and Siri go through this actor (owned by `IngestionService`).
///
/// Each operation uses a **fresh `ModelContext`**: the app edits the same store on its main context, and a long-lived
/// background context would keep stale copies of objects the user has since changed (an account's kind, a rule).
/// Operations hand each other `PersistentIdentifier`s, never model objects.
@ModelActor
public actor TransactionStore {
    public enum CommitOutcome: Sendable, Equatable {
        case saved(UUID)
        case duplicate
    }

    // MARK: Raw messages

    public func insertRawMessage(
        body: String,
        sender: String?,
        receivedAt: Date,
        source: TransactionSource = .sms
    ) throws -> PersistentIdentifier {
        let context = makeContext()
        let raw = RawMessage(body: body, sender: sender, receivedAt: receivedAt, source: source)
        context.insert(raw)
        try save(context)
        return raw.persistentModelID
    }

    public func updateStatus(_ rawID: PersistentIdentifier, status: MessageStatus, reason: String?) throws {
        let context = makeContext()
        let raw = try rawMessage(rawID, in: context)
        raw.status = status
        raw.failureReason = reason
        raw.parserVersion = ParsingPipeline.version
        try save(context)
    }

    // MARK: Dedup + save

    /// Dedup check and save in one actor-isolated call, so two concurrent ingestions of the same SMS
    /// cannot both pass the duplicate check.
    public func commit(
        _ parsed: ParsedTransaction,
        for rawID: PersistentIdentifier,
        source: TransactionSource,
        status: MessageStatus,
        reason: String?
    ) throws -> CommitOutcome {
        let context = makeContext()
        let raw = try rawMessage(rawID, in: context)
        if try isDuplicate(
            parsed, bodyHash: raw.bodyHash, receivedAt: raw.receivedAt, sender: raw.sender, excluding: rawID, in: context
        ) {
            raw.status = .duplicate
            raw.failureReason = nil
            raw.parserVersion = ParsingPipeline.version
            try save(context)
            return .duplicate
        }
        return .saved(try insertTransaction(parsed, raw: raw, source: source, status: status, reason: reason, in: context))
    }

    /// A message is a duplicate if an earlier accepted message has the same body hash, or an existing
    /// transaction has the same amount + currency + account (bankName, last4 or merge alias) within ±3 minutes.
    public func findDuplicate(
        of parsed: ParsedTransaction,
        bodyHash: String,
        receivedAt: Date,
        sender: String?,
        excluding rawID: PersistentIdentifier? = nil
    ) throws -> Bool {
        try isDuplicate(
            parsed, bodyHash: bodyHash, receivedAt: receivedAt, sender: sender, excluding: rawID, in: makeContext()
        )
    }

    @discardableResult
    public func saveTransaction(
        _ parsed: ParsedTransaction,
        for rawID: PersistentIdentifier,
        source: TransactionSource,
        status: MessageStatus = .parsed,
        reason: String? = nil
    ) throws -> UUID {
        let context = makeContext()
        let raw = try rawMessage(rawID, in: context)
        return try insertTransaction(parsed, raw: raw, source: source, status: status, reason: reason, in: context)
    }

    // MARK: Maintenance & diagnostics

    public func deleteAll() throws {
        try TransactionEditor(context: makeContext()).deleteAllData()
    }

    /// Seeds default categories, fixes up legacy accounts and categorises anything uncategorised.
    /// Returns how many transactions were back-filled.
    @discardableResult
    public func prepare() throws -> Int {
        let context = makeContext()
        try CategoryService.ensureDefaultCategories(in: context)
        try AccountService.prepare(in: context)
        let backfilled = try CategoryService.backfillUncategorized(in: context)
        try save(context)
        return backfilled
    }

    /// Manual entry (Siri / Shortcuts). Same logic the app uses on its main context.
    public func addManual(_ draft: TransactionDraft) throws -> TransactionSnapshot {
        TransactionSnapshot(try TransactionEditor(context: makeContext()).addManual(draft))
    }

    public func facts(in interval: DateInterval) throws -> [TransactionFact] {
        let start = interval.start
        let end = interval.end
        return try makeContext().fetch(
            FetchDescriptor<Transaction>(predicate: #Predicate { $0.occurredAt >= start && $0.occurredAt < end })
        ).map { TransactionFact($0) }
    }

    public func categoryNames() throws -> [String] {
        try makeContext().fetch(FetchDescriptor<TransactionCategory>(sortBy: [SortDescriptor(\.sortOrder)])).map(\.name)
    }

    public func accountSnapshots() throws -> [AccountSnapshot] {
        try makeContext().fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.displayName)])).map { AccountSnapshot($0) }
    }

    public func dashboardSnapshot(now: Date) throws -> DashboardSnapshot {
        try DashboardSnapshot.load(in: makeContext(), now: now)
    }

    public func transactionSnapshot(id: UUID) throws -> TransactionSnapshot? {
        var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try makeContext().fetch(descriptor).first.map { TransactionSnapshot($0) }
    }

    /// "Not an expense" from a notification: same as the Review queue's "Not a transaction". Returns false if gone.
    public func markNotATransaction(id: UUID) throws -> Bool {
        let context = makeContext()
        var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let transaction = try context.fetch(descriptor).first else { return false }
        try TransactionEditor(context: context).markNotATransaction(transaction)
        return true
    }

    public func ruleCount() throws -> Int {
        try makeContext().fetchCount(FetchDescriptor<MerchantRule>())
    }

    /// Deletes ignored messages (OTPs, promotions, reminders) received before `cutoff`. Returns how many.
    @discardableResult
    public func purgeIgnoredMessages(olderThan cutoff: Date) throws -> Int {
        let context = makeContext()
        let ignored = MessageStatus.ignored.rawValue
        let expired = try context.fetch(
            FetchDescriptor<RawMessage>(predicate: #Predicate { $0.statusRaw == ignored && $0.receivedAt < cutoff })
        )
        guard !expired.isEmpty else { return 0 }
        for message in expired { context.delete(message) }
        try save(context)
        return expired.count
    }

    /// When the most recent message from the Shortcuts automation (not the Simulate tab) arrived.
    public func lastAutomationMessageDate() throws -> Date? {
        let sms = TransactionSource.sms.rawValue
        var descriptor = FetchDescriptor<RawMessage>(
            predicate: #Predicate { $0.sourceRaw == sms },
            sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try makeContext().fetch(descriptor).first?.receivedAt
    }

    public func rawMessageSnapshots() throws -> [RawMessageSnapshot] {
        try makeContext().fetch(FetchDescriptor<RawMessage>(sortBy: [SortDescriptor(\.receivedAt)]))
            .map(RawMessageSnapshot.init)
    }

    public func transactionSnapshots() throws -> [TransactionSnapshot] {
        try makeContext().fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.occurredAt)]))
            .map(TransactionSnapshot.init)
    }

    public func accountCount() throws -> Int {
        try makeContext().fetchCount(FetchDescriptor<Account>())
    }

    // MARK: Private

    private func makeContext() -> ModelContext {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        return context
    }

    private func isDuplicate(
        _ parsed: ParsedTransaction,
        bodyHash: String,
        receivedAt: Date,
        sender: String?,
        excluding rawID: PersistentIdentifier?,
        in context: ModelContext
    ) throws -> Bool {
        let sameBody = try context.fetch(
            FetchDescriptor<RawMessage>(predicate: #Predicate { $0.bodyHash == bodyHash })
        )
        if sameBody.contains(where: { $0.persistentModelID != rawID && IngestionRules.blocksIdenticalBody($0.status) }) {
            return true
        }

        let occurredAt = parsed.occurredAt ?? receivedAt
        let lower = occurredAt.addingTimeInterval(-IngestionRules.duplicateWindow)
        let upper = occurredAt.addingTimeInterval(IngestionRules.duplicateWindow)
        let nearby = try context.fetch(
            FetchDescriptor<Transaction>(predicate: #Predicate { $0.occurredAt >= lower && $0.occurredAt <= upper })
        )
        let bank = IngestionRules.bankName(for: parsed, sender: sender)
        return nearby.contains { existing in
            existing.amount == parsed.amount
                && existing.currency == parsed.currency
                && existing.account?.matches(bankName: bank, last4: parsed.last4) == true
        }
    }

    private func insertTransaction(
        _ parsed: ParsedTransaction,
        raw: RawMessage,
        source: TransactionSource,
        status: MessageStatus,
        reason: String?,
        in context: ModelContext
    ) throws -> UUID {
        let account = try AccountService.upsert(
            bankName: IngestionRules.bankName(for: parsed, sender: raw.sender),
            last4: parsed.last4,
            detectedKind: parsed.accountKind,
            in: context
        )
        let transaction = Transaction(
            amount: parsed.amount,
            currency: parsed.currency,
            type: parsed.type,
            merchant: parsed.merchant,
            occurredAt: parsed.occurredAt ?? raw.receivedAt,
            balanceAfter: parsed.balanceAfter,
            confidence: parsed.confidence,
            source: source
        )
        context.insert(transaction)
        transaction.account = account
        transaction.rawMessage = raw

        // Merchant rules (rename + category), then built-in keywords.
        let resolution = try CategoryService.resolve(merchant: parsed.merchant, type: parsed.type, in: context)
        transaction.category = resolution.category
        if let renamed = resolution.renamedMerchant {
            transaction.merchant = renamed
        }
        resolution.rule?.hitCount += 1
        raw.status = status
        raw.failureReason = reason
        raw.parserVersion = ParsingPipeline.version
        try save(context)
        return transaction.id
    }

    private func rawMessage(_ id: PersistentIdentifier, in context: ModelContext) throws -> RawMessage {
        var descriptor = FetchDescriptor<RawMessage>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        guard let raw = try context.fetch(descriptor).first else { throw StoreError.rawMessageNotFound }
        return raw
    }

    private func save(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
