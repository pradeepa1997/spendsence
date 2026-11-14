import Foundation
import Testing
@testable import SpendCore

@Suite("Automation health")
struct AutomationHealthTests {
    let now = TestSupport.t0

    @Test func neverReceived() {
        #expect(AutomationHealth.evaluate(lastSMSAt: nil, now: now) == .neverReceived)
    }

    @Test func recentIsHealthy() {
        #expect(AutomationHealth.evaluate(lastSMSAt: now.addingTimeInterval(-3_600), now: now) == .healthy)
        #expect(AutomationHealth.evaluate(lastSMSAt: now.addingTimeInterval(-5 * 86_400), now: now) == .healthy)
    }

    @Test func moreThanFiveDaysIsStale() {
        #expect(AutomationHealth.evaluate(lastSMSAt: now.addingTimeInterval(-6 * 86_400), now: now) == .stale(days: 6))
    }

    @Test func simulatedMessagesDoNotCountAsAutomation() async throws {
        let (service, store) = try TestSupport.makeService()
        _ = await service.ingest(body: "Txn of LKR 850.00 at PICKME FOOD using card **9012 approved.", sender: nil,
                                 receivedAt: now, source: .simulated)
        #expect(try await store.lastAutomationMessageDate() == nil)

        _ = await service.ingest(body: "Your OTP is 123456", sender: nil, receivedAt: now.addingTimeInterval(60))
        #expect(try await store.lastAutomationMessageDate() == now.addingTimeInterval(60))
        #expect(try await store.rawMessageSnapshots().map(\.source) == [.simulated, .sms])
    }
}

@Suite("Ignored message purge")
struct PurgeTests {
    let t0 = TestSupport.t0

    @Test func deletesOnlyIgnoredMessagesOlderThanSevenDays() async throws {
        let (service, store) = try TestSupport.makeService()
        _ = await service.ingest(body: "Your OTP is 111111", sender: nil, receivedAt: t0)                 // old, ignored
        _ = await service.ingest(body: "Your OTP is 222222", sender: nil, receivedAt: t0.addingTimeInterval(6 * 86_400)) // recent
        _ = await service.ingest(body: "Txn of LKR 850.00 at PICKME FOOD using card **9012 approved.", sender: nil,
                                 receivedAt: t0)                                                           // old, parsed

        let purged = await service.purgeExpiredIgnoredMessages(now: t0.addingTimeInterval(8 * 86_400))
        #expect(purged == 1)
        let remaining = try await store.rawMessageSnapshots()
        #expect(remaining.count == 2)
        #expect(!remaining.contains { $0.body == "Your OTP is 111111" })
        #expect(try await store.transactionSnapshots().count == 1)
    }
}

@Suite("Real bank formats end to end")
struct BankIngestionTests {
    let t0 = ISO8601DateFormatter().date(from: "2026-11-14T18:00:00Z") ?? .now

    @Test func hnbCardAndAccountAlertsShareOneAccount() async throws {
        let (service, store) = try TestSupport.makeService()
        let card = await service.ingest(
            body: "HNB SMS ALERT:INTERNET, Account:1120***4821,Location:UBER EATS, LK,Amount(Approx.):570.47 LKR,Av.Bal:1,234.56 LKR,Date:14.11.26,Time:18:26, Hot Line:0112462462",
            sender: "HNB", receivedAt: t0
        )
        let account = await service.ingest(
            body: "LKR 100.00 credited to Ac No:11202XXXXX21 on 14/11/26 16:37:48 Reason:CEFT-RELOAD Bal:LKR 681.85 Protect from scams *DO NOT SHARE ACCOUNT DETAILS /OTP* Hotline 0112462462",
            sender: "HNB", receivedAt: t0
        )
        #expect(card.status == .parsed)
        #expect(account.status == .parsed)
        #expect(try await store.accountCount() == 1)
        #expect(try await store.transactionSnapshots().allSatisfy { $0.accountDisplayName == "HNB ••4821" })
    }

    @Test func shortEndingFirstIsUpgradedToLongerEnding() async throws {
        let (service, store) = try TestSupport.makeService()
        _ = await service.ingest(
            body: "LKR 100.00 credited to Ac No:11202XXXXX21 on 14/11/26 16:37:48 Reason:CEFT-RELOAD Bal:LKR 681.85",
            sender: "HNB", receivedAt: t0
        )
        _ = await service.ingest(
            body: "HNB SMS ALERT:POS, Account:1120***4821,Location:KEELLS SUPER, LK,Amount(Approx.):2,150.00 LKR,Av.Bal:987.10 LKR,Date:14.11.26,Time:17:05, Hot Line:0112462462",
            sender: "HNB", receivedAt: t0
        )
        #expect(try await store.accountCount() == 1)
        #expect(try await store.transactionSnapshots().first?.last4 == "4821")
    }

    @Test func differentBanksWithSameEndingStaySeparate() async throws {
        let (service, store) = try TestSupport.makeService()
        _ = await service.ingest(
            body: "ALERT CR CARD: Livon Pharmacy CARD**3141 DEBITED LKR 4,452.56 ON (14/NOV/2026 17:46) AUTHCODE 902114 AVBAL LKR 52,136.34",
            sender: "DFCC", receivedAt: t0
        )
        _ = await service.ingest(
            body: "Card 481546******3141 Debited LKR 5,580.00 JAVA LOUNGE PVT LTD PILIYAN 2026-11-13 19:51:18 Avl Bal 412,046.32.",
            sender: "NDB", receivedAt: t0
        )
        #expect(try await store.accountCount() == 2)
    }

    @Test(arguments: [
        (nil, nil, true), ("1234", "1234", true), ("95", "7795", true), ("7795", "95", true),
        ("95", "7796", false), ("5", "7795", false), ("1234", nil, false),
    ] as [(String?, String?, Bool)])
    func accountEndingMatching(a: String?, b: String?, expected: Bool) {
        #expect(IngestionRules.sameAccount(a, b) == expected)
    }
}
