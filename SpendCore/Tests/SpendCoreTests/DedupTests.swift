import Foundation
import Testing
@testable import SpendCore

@Suite("Dedup")
struct DedupTests {
    let t0 = TestSupport.t0

    @Test func identicalBodyTwiceIsOneTransaction() async throws {
        let (service, store) = try TestSupport.makeService()
        let body = "LKR 2,450.00 debited from card ending 1234 at KEELLS SUPER on 12/09/26. Avl Bal LKR 45,210.50"

        let first = await service.ingest(body: body, sender: "BANKA", receivedAt: t0)
        let second = await service.ingest(body: body, sender: "BANKA", receivedAt: t0.addingTimeInterval(30))

        #expect(first.status == .parsed)
        #expect(second.status == .duplicate)
        #expect(try await store.transactionSnapshots().count == 1)
        let statuses = try await store.rawMessageSnapshots().map(\.status)
        #expect(statuses.filter { $0 == .duplicate }.count == 1)
        #expect(statuses.count == 2)
    }

    @Test func sameAmountAndAccountOneMinuteApartIsDuplicate() async throws {
        let (service, store) = try TestSupport.makeService()
        let a = await service.ingest(
            body: "You have spent LKR 2,450.00 at KEELLS SUPER on your card ending 1234.",
            sender: "BANKD", receivedAt: t0
        )
        let b = await service.ingest(
            body: "LKR 2,450.00 paid at KEELLS SUPER using card ending 1234.",
            sender: "BANKD", receivedAt: t0.addingTimeInterval(60)
        )
        #expect(a.status == .parsed)
        #expect(b.status == .duplicate)
        #expect(try await store.transactionSnapshots().count == 1)
    }

    @Test func sameAmountTenMinutesApartIsTwoTransactions() async throws {
        let (service, store) = try TestSupport.makeService()
        let a = await service.ingest(
            body: "You have spent LKR 2,450.00 at KEELLS SUPER on your card ending 1234.",
            sender: "BANKD", receivedAt: t0
        )
        let b = await service.ingest(
            body: "LKR 2,450.00 paid at KEELLS SUPER using card ending 1234.",
            sender: "BANKD", receivedAt: t0.addingTimeInterval(600)
        )
        #expect(a.status == .parsed)
        #expect(b.status == .parsed)
        #expect(try await store.transactionSnapshots().count == 2)
    }

    @Test func sameAmountDifferentCardIsNotDuplicate() async throws {
        let (service, store) = try TestSupport.makeService()
        _ = await service.ingest(
            body: "You have spent LKR 2,450.00 at KEELLS SUPER on your card ending 1234.", sender: "BANKD", receivedAt: t0
        )
        let b = await service.ingest(
            body: "You have spent LKR 2,450.00 at KEELLS SUPER on your card ending 9999.", sender: "BANKD", receivedAt: t0
        )
        #expect(b.status == .parsed)
        #expect(try await store.transactionSnapshots().count == 2)
    }

    @Test func failedMessageDoesNotBlockLaterIdenticalBody() async throws {
        // Only accepted messages block an identical body; an earlier failure must not swallow a retry.
        let (service, store) = try TestSupport.makeService()
        let body = "LKR 100.00 debited from card ending 4321 at TEST SHOP on 12/09/26."
        let failedID = try await store.insertRawMessage(body: body, sender: nil, receivedAt: t0)
        try await store.updateStatus(failedID, status: .failed, reason: "earlier failure")

        let retry = await service.ingest(body: body, sender: nil, receivedAt: t0.addingTimeInterval(5))
        #expect(retry.status == .parsed)
        #expect(try await store.transactionSnapshots().count == 1)
    }
}
