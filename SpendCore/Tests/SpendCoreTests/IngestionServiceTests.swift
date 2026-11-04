import Foundation
import Testing
@testable import SpendCore

@Suite("IngestionService")
struct IngestionServiceTests {
    let t0 = TestSupport.t0

    @Test func rawMessageIsPersistedEvenWhenIgnored() async throws {
        let (service, store) = try TestSupport.makeService()
        let result = await service.ingest(body: "Your OTP is 482913. Do not share it.", sender: "BANKA", receivedAt: t0)

        #expect(result.status == .ignored)
        #expect(result.summary == "Ignored: OTP")
        #expect(result.transactionID == nil)
        let raws = try await store.rawMessageSnapshots()
        #expect(raws.count == 1)
        #expect(raws.first?.status == .ignored)
        #expect(raws.first?.failureReason == "OTP")
        #expect(try await store.transactionSnapshots().isEmpty)
    }

    @Test func accountIsReusedAcrossMessagesFromSameCard() async throws {
        let (service, store) = try TestSupport.makeService()
        let a = await service.ingest(
            body: "LKR 2,450.00 debited from card ending 1234 at KEELLS SUPER on 12/09/26.", sender: "BANKA", receivedAt: t0
        )
        let b = await service.ingest(
            body: "Rs. 990 debited from card ending 1234 at KFC MAJESTIC CITY on 12/09/26.", sender: "BANKA",
            receivedAt: t0.addingTimeInterval(3600)
        )
        #expect(a.status == .parsed)
        #expect(b.status == .parsed)
        #expect(try await store.transactionSnapshots().count == 2)
        #expect(try await store.accountCount() == 1)
        #expect(try await store.transactionSnapshots().first?.accountDisplayName == "Bank A ••1234")
    }

    @Test func failurePathSetsFailedAndDoesNotThrow() async throws {
        let (service, store) = try TestSupport.makeService(stepHook: { step in
            if step == .commit { throw TestSupport.InjectedFailure() }
        })
        let result = await service.ingest(
            body: "LKR 2,450.00 debited from card ending 1234 at KEELLS SUPER on 12/09/26.", sender: "BANKA", receivedAt: t0
        )
        #expect(result.status == .failed)
        #expect(result.summary == "Failed: Injected failure")
        let raws = try await store.rawMessageSnapshots()
        #expect(raws.count == 1)
        #expect(raws.first?.status == .failed)
        #expect(raws.first?.failureReason == "Injected failure")
        #expect(try await store.transactionSnapshots().isEmpty)
    }

    @Test func unavailableStoreFailsGracefully() async {
        let service = IngestionService(containerResult: .failure(TestSupport.InjectedFailure()))
        let result = await service.ingest(body: "LKR 1 debited", sender: nil)
        #expect(result.status == .failed)
    }

    @Test func successSummaryAndLinking() async throws {
        let (service, store) = try TestSupport.makeService()
        let result = await service.ingest(
            body: "LKR 2,450.00 debited from card ending 1234 at KEELLS SUPER on 12/09/26.", sender: "BANKA", receivedAt: t0
        )
        #expect(result.summary == "Logged LKR 2,450.00 – Keells Super")
        let transaction = try #require(try await store.transactionSnapshots().first)
        let raw = try #require(try await store.rawMessageSnapshots().first)
        #expect(result.transactionID == transaction.id)
        #expect(transaction.rawMessageID == raw.id)
        #expect(raw.transactionID == transaction.id)
        #expect(transaction.source == .sms)
        #expect(transaction.occurredAt == t0) // date-only template date takes receivedAt's time of day
    }

    @Test func lowConfidenceIsStillSavedAsNeedsReview() async throws {
        let (service, store) = try TestSupport.makeService()
        let result = await service.ingest(
            body: "Salary of LKR 185,000.00 received to your A/C ending 5678 on 25/08.", sender: "BANKD", receivedAt: t0
        )
        #expect(result.status == .needsReview)
        #expect(result.summary == "Logged for review: credit LKR 185,000.00")
        let transaction = try #require(try await store.transactionSnapshots().first)
        #expect(transaction.confidence == 0.65)
        #expect(transaction.type == .credit)
        #expect(try await store.rawMessageSnapshots().first?.status == .needsReview)
    }

    @Test func noAmountIsNeedsReviewWithoutTransaction() async throws {
        let (service, store) = try TestSupport.makeService()
        let result = await service.ingest(
            body: "Your card ending 1234 was debited. Please check the app for details.", sender: "BANKA", receivedAt: t0
        )
        #expect(result.status == .needsReview)
        #expect(try await store.transactionSnapshots().isEmpty)
        #expect(try await store.rawMessageSnapshots().first?.failureReason == "no amount")
    }

    @Test func simulatedSourceIsRecorded() async throws {
        let (service, store) = try TestSupport.makeService()
        _ = await service.ingest(
            body: "Txn of LKR 850.00 at PICKME FOOD using card **9012 approved.", sender: nil, receivedAt: t0,
            source: .simulated
        )
        #expect(try await store.transactionSnapshots().first?.source == .simulated)
    }

    @Test func deleteAllDataEmptiesTheStore() async throws {
        let (service, store) = try TestSupport.makeService()
        _ = await service.ingest(body: "Txn of LKR 850.00 at PICKME FOOD using card **9012 approved.", sender: nil, receivedAt: t0)
        try await service.deleteAllData()
        #expect(try await store.transactionSnapshots().isEmpty)
        #expect(try await store.rawMessageSnapshots().isEmpty)
        #expect(try await store.accountCount() == 0)
    }
}
