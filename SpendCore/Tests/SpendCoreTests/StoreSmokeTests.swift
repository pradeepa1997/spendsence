import Foundation
import Testing
@testable import SpendCore

@Suite("Store smoke tests")
struct StoreSmokeTests {
    @Test func insertRawMessageThenSaveTransaction() async throws {
        let store = TransactionStore(modelContainer: try StoreFactory.makeContainer(inMemory: true))
        let rawID = try await store.insertRawMessage(body: "LKR 100.00 debited", sender: "TEST", receivedAt: .now)

        let parsed = ParsedTransaction(
            amount: 100, type: .debit, merchant: "Test Shop", last4: "4321", bankName: "Test Bank", confidence: 0.9
        )
        let transactionID = try await store.saveTransaction(parsed, for: rawID, source: .simulated)

        let raws = try await store.rawMessageSnapshots()
        let transactions = try await store.transactionSnapshots()
        #expect(raws.count == 1)
        #expect(raws.first?.status == .parsed)
        #expect(raws.first?.transactionID == transactionID)
        #expect(transactions.count == 1)
        #expect(transactions.first?.rawMessageID == raws.first?.id)
        #expect(transactions.first?.accountDisplayName == "Test Bank ••4321")
        #expect(try await store.accountCount() == 1)
    }

    @Test func rawMessageIsPendingUntilProcessed() async throws {
        let store = TransactionStore(modelContainer: try StoreFactory.makeContainer(inMemory: true))
        _ = try await store.insertRawMessage(body: "  hello  ", sender: nil, receivedAt: .now)
        let raw = try #require(try await store.rawMessageSnapshots().first)
        #expect(raw.status == .pending)
        #expect(raw.parserVersion == ParsingPipeline.version)
    }

    @Test func bodyHashIgnoresSurroundingWhitespace() {
        #expect(BodyHasher.hash("  abc \n") == BodyHasher.hash("abc"))
        #expect(BodyHasher.hash("abc") != BodyHasher.hash("abd"))
        #expect(BodyHasher.hash("abc").count == 64)
    }

    @Test func accountDisplayNameDefaults() {
        #expect(Account.defaultDisplayName(bankName: "HNB", last4: "1234") == "HNB ••1234")
        #expect(Account.defaultDisplayName(bankName: "HNB", last4: nil) == "HNB (unknown)")
    }
}
