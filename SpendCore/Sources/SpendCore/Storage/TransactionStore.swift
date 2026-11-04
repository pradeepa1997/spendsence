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

    /// Statuses whose body hash blocks an identical later message.
    static func blocksIdenticalBody(_ status: MessageStatus) -> Bool {
        switch status {
        case .parsed, .needsReview, .duplicate: true
        case .pending, .ignored, .failed: false
        }
    }
}

/// All SwiftData writes go through this actor (owned by `IngestionService`).
@ModelActor
public actor TransactionStore {
    public enum CommitOutcome: Sendable, Equatable {
        case saved(UUID)
        case duplicate
    }

    // MARK: Raw messages

    public func insertRawMessage(body: String, sender: String?, receivedAt: Date) throws -> PersistentIdentifier {
        let raw = RawMessage(body: body, sender: sender, receivedAt: receivedAt)
        modelContext.insert(raw)
        try saveOrRollback()
        return raw.persistentModelID
    }

    public func updateStatus(_ rawID: PersistentIdentifier, status: MessageStatus, reason: String?) throws {
        let raw = try rawMessage(rawID)
        raw.status = status
        raw.failureReason = reason
        raw.parserVersion = ParsingPipeline.version
        try saveOrRollback()
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
        let raw = try rawMessage(rawID)
        if try findDuplicate(
            of: parsed, bodyHash: raw.bodyHash, receivedAt: raw.receivedAt, sender: raw.sender, excluding: rawID
        ) {
            raw.status = .duplicate
            raw.failureReason = nil
            raw.parserVersion = ParsingPipeline.version
            try saveOrRollback()
            return .duplicate
        }
        let id = try saveTransaction(parsed, for: rawID, source: source, status: status, reason: reason)
        return .saved(id)
    }

    /// A message is a duplicate if an earlier accepted message has the same body hash, or an existing
    /// transaction has the same amount + currency + account (bankName, last4) within ±3 minutes.
    public func findDuplicate(
        of parsed: ParsedTransaction,
        bodyHash: String,
        receivedAt: Date,
        sender: String?,
        excluding rawID: PersistentIdentifier? = nil
    ) throws -> Bool {
        let sameBody = try modelContext.fetch(
            FetchDescriptor<RawMessage>(predicate: #Predicate { $0.bodyHash == bodyHash })
        )
        if sameBody.contains(where: { $0.persistentModelID != rawID && IngestionRules.blocksIdenticalBody($0.status) }) {
            return true
        }

        let occurredAt = parsed.occurredAt ?? receivedAt
        let lower = occurredAt.addingTimeInterval(-IngestionRules.duplicateWindow)
        let upper = occurredAt.addingTimeInterval(IngestionRules.duplicateWindow)
        let nearby = try modelContext.fetch(
            FetchDescriptor<Transaction>(predicate: #Predicate { $0.occurredAt >= lower && $0.occurredAt <= upper })
        )
        let bank = IngestionRules.bankName(for: parsed, sender: sender)
        return nearby.contains { existing in
            existing.amount == parsed.amount
                && existing.currency == parsed.currency
                && existing.account?.bankName == bank
                && existing.account?.last4 == parsed.last4
        }
    }

    @discardableResult
    public func saveTransaction(
        _ parsed: ParsedTransaction,
        for rawID: PersistentIdentifier,
        source: TransactionSource,
        status: MessageStatus = .parsed,
        reason: String? = nil
    ) throws -> UUID {
        let raw = try rawMessage(rawID)
        let account = try upsertAccount(
            bankName: IngestionRules.bankName(for: parsed, sender: raw.sender),
            last4: parsed.last4
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
        modelContext.insert(transaction)
        transaction.account = account
        transaction.rawMessage = raw
        raw.status = status
        raw.failureReason = reason
        raw.parserVersion = ParsingPipeline.version
        try saveOrRollback()
        return transaction.id
    }

    /// Matches on (bankName, last4); a nil last4 maps to a single "<bank> (unknown)" account.
    /// Does not save; callers save as part of their own unit of work.
    public func upsertAccount(bankName: String, last4: String?) throws -> Account {
        let candidates = try modelContext.fetch(
            FetchDescriptor<Account>(predicate: #Predicate { $0.bankName == bankName })
        )
        if let existing = candidates.first(where: { $0.last4 == last4 }) {
            return existing
        }
        let account = Account(bankName: bankName, last4: last4)
        modelContext.insert(account)
        return account
    }

    // MARK: Maintenance & diagnostics

    public func deleteAll() throws {
        for transaction in try modelContext.fetch(FetchDescriptor<Transaction>()) { modelContext.delete(transaction) }
        for raw in try modelContext.fetch(FetchDescriptor<RawMessage>()) { modelContext.delete(raw) }
        for account in try modelContext.fetch(FetchDescriptor<Account>()) { modelContext.delete(account) }
        try saveOrRollback()
    }

    public func rawMessageSnapshots() throws -> [RawMessageSnapshot] {
        try modelContext.fetch(FetchDescriptor<RawMessage>(sortBy: [SortDescriptor(\.receivedAt)]))
            .map(RawMessageSnapshot.init)
    }

    public func transactionSnapshots() throws -> [TransactionSnapshot] {
        try modelContext.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.occurredAt)]))
            .map(TransactionSnapshot.init)
    }

    public func accountCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<Account>())
    }

    // MARK: Private

    private func rawMessage(_ id: PersistentIdentifier) throws -> RawMessage {
        guard let raw = self[id, as: RawMessage.self] else { throw StoreError.rawMessageNotFound }
        return raw
    }

    private func saveOrRollback() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
