import Foundation
import SwiftData

public struct IngestionResult: Sendable, Equatable {
    public let status: MessageStatus
    /// Human-readable, e.g. "Logged LKR 2,450.00 – Keells Super" or "Ignored: OTP".
    public let summary: String
    public let transactionID: UUID?

    public init(status: MessageStatus, summary: String, transactionID: UUID? = nil) {
        self.status = status
        self.summary = summary
        self.transactionID = transactionID
    }
}

/// Points where tests can inject a failure.
enum IngestionStep: Sendable, Equatable {
    case parse
    case commit
}

/// The single entry point for getting an SMS into the store. Used by the App Intent and the Simulate tab.
public actor IngestionService {
    /// Backed by `SharedStore`, the same container the SwiftUI app uses.
    public static let shared = IngestionService(containerResult: SharedStore.containerResult)

    nonisolated let store: TransactionStore?
    private let storeError: String?
    private let pipeline: ParsingPipeline
    private let stepHook: (@Sendable (IngestionStep) throws -> Void)?

    public init(container: ModelContainer, pipeline: ParsingPipeline = ParsingPipeline()) {
        self.init(containerResult: .success(container), pipeline: pipeline, stepHook: nil)
    }

    init(
        containerResult: Result<ModelContainer, any Error>,
        pipeline: ParsingPipeline = ParsingPipeline(),
        stepHook: (@Sendable (IngestionStep) throws -> Void)? = nil
    ) {
        switch containerResult {
        case .success(let container):
            store = TransactionStore(modelContainer: container)
            storeError = nil
        case .failure(let error):
            store = nil
            storeError = error.localizedDescription
        }
        self.pipeline = pipeline
        self.stepHook = stepHook
    }

    /// Persist raw → parse → (ignore | dedup → save). Never throws; failures are recorded on the RawMessage.
    public func ingest(
        body: String,
        sender: String?,
        receivedAt: Date = .now,
        source: TransactionSource = .sms
    ) async -> IngestionResult {
        guard let store else {
            return IngestionResult(status: .failed, summary: "Failed: storage unavailable (\(storeError ?? "unknown error"))")
        }
        let sender = sender?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSender = (sender?.isEmpty ?? true) ? nil : sender

        // 1. The raw text must never be lost.
        let rawID: PersistentIdentifier
        do {
            rawID = try await store.insertRawMessage(body: body, sender: normalizedSender, receivedAt: receivedAt)
        } catch {
            return IngestionResult(status: .failed, summary: "Failed: could not save message (\(error.localizedDescription))")
        }

        do {
            // 2. Parse.
            try stepHook?(.parse)
            let outcome = pipeline.run(body: body, sender: normalizedSender, receivedAt: receivedAt)

            let parsed: ParsedTransaction
            let status: MessageStatus
            let reason: String?
            switch outcome {
            case .ignored(let why):
                // 3. Ignored messages keep their RawMessage but produce no transaction.
                try await store.updateStatus(rawID, status: .ignored, reason: why)
                return IngestionResult(status: .ignored, summary: "Ignored: \(why)")
            case .needsReview(nil, let why):
                try await store.updateStatus(rawID, status: .needsReview, reason: why)
                return IngestionResult(status: .needsReview, summary: "Needs review: \(why)")
            case .needsReview(let candidate?, let why):
                parsed = candidate
                status = .needsReview
                reason = why
            case .parsed(let candidate):
                parsed = candidate
                status = .parsed
                reason = nil
            }

            // 4 + 5. Dedup, then upsert account and save, atomically inside the store actor.
            try stepHook?(.commit)
            switch try await store.commit(parsed, for: rawID, source: source, status: status, reason: reason) {
            case .duplicate:
                return IngestionResult(status: .duplicate, summary: "Duplicate: \(Self.describe(parsed)) already logged")
            case .saved(let transactionID):
                return IngestionResult(
                    status: status,
                    summary: Self.savedSummary(parsed, status: status),
                    transactionID: transactionID
                )
            }
        } catch {
            // 6. Record the failure; never rethrow.
            let reason = error.localizedDescription
            try? await store.updateStatus(rawID, status: .failed, reason: reason)
            return IngestionResult(status: .failed, summary: "Failed: \(reason)")
        }
    }

    /// Dev convenience: wipes transactions, messages and accounts.
    public func deleteAllData() async throws {
        guard let store else { return }
        try await store.deleteAll()
    }

    // MARK: Summaries

    static func describe(_ parsed: ParsedTransaction) -> String {
        var text = AmountFormatter.string(parsed.amount, currency: parsed.currency)
        if let merchant = parsed.merchant {
            text += " – \(merchant)"
        }
        return text
    }

    static func savedSummary(_ parsed: ParsedTransaction, status: MessageStatus) -> String {
        let kind = switch parsed.type {
        case .credit: "credit "
        case .refund: "refund "
        case .transfer: "transfer "
        case .debit, .unknown: ""
        }
        let core = kind + describe(parsed)
        return status == .needsReview ? "Logged for review: \(core)" : "Logged \(core)"
    }
}
