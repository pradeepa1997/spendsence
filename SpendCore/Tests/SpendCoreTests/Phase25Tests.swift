import Foundation
import SwiftData
import Testing
@testable import SpendCore

// MARK: - Account kinds

@Suite("Account kinds")
struct AccountKindTests {
    let pipeline = ParsingPipeline()

    @Test(arguments: [
        ("hnb_card_online", AccountKind.debitCard),
        ("hnb_account_credit", AccountKind.bankAccount),
        ("dfcc_credit_card", AccountKind.creditCard),
        ("dfcc_account_debit", AccountKind.bankAccount),
        ("ndb_credit_card", AccountKind.creditCard),
        ("seylan_account_refund", AccountKind.bankAccount),
        ("seylan_credit_card", AccountKind.creditCard),
        ("peoples_account_debit", AccountKind.bankAccount),
    ])
    func templatesDeclareTheirKind(fixtureID: String, expected: AccountKind) throws {
        let fixture = try #require(SMSFixture.all.first { $0.id == fixtureID })
        guard case .parsed(let parsed) = pipeline.run(body: fixture.body, sender: fixture.sender, receivedAt: fixture.receivedDate)
        else {
            Issue.record("[\(fixtureID)] did not parse")
            return
        }
        #expect(parsed.accountKind == expected, "[\(fixtureID)]")
    }

    @Test(arguments: [
        ("LKR 4,800.00 spent on your credit card ending 3321 at ARPICO.", AccountKind?.some(.creditCard)),
        ("LKR 600.00 spent on your debit card ending 3344 at SPAR.", AccountKind?.some(.debitCard)),
        ("LKR 600.00 paid to DIALOG from A/C ending 3344.", AccountKind?.some(.bankAccount)),
        ("You have spent LKR 3,450.75 at CARGILLS on your card ending 2211.", AccountKind?.none),
    ])
    func genericParserInfersKind(body: String, expected: AccountKind?) {
        #expect(GenericParser.inferAccountKind(from: Normalizer.normalize(body).text) == expected)
    }

    @Test func refinementNeverDowngrades() {
        #expect(AccountKind.unknown.refined(with: .creditCard) == .creditCard)
        #expect(AccountKind.debitCard.refined(with: .bankAccount) == .bankAccount)
        #expect(AccountKind.bankAccount.refined(with: .debitCard) == .bankAccount)
        #expect(AccountKind.creditCard.refined(with: .bankAccount) == .creditCard)
        #expect(AccountKind.cash.refined(with: nil) == .cash)
        #expect(AccountKind.bankAccount.refined(with: .unknown) == .bankAccount)
    }
}

// MARK: - Balance maths

@Suite("Balance calculator")
struct BalanceCalculatorTests {
    let t0 = Date(timeIntervalSince1970: 1_794_000_000)

    func at(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3_600) }

    @Test func reportedBalanceThenEstimatedAdjustments() {
        let events: [BalanceEvent] = [
            BalanceEvent(date: at(0), effect: -500, reportedBalance: 10_000),
            BalanceEvent(date: at(1), effect: -250),
            BalanceEvent(date: at(2), effect: 1_000),
        ]
        let balance = BalanceCalculator.balance(kind: .bankAccount, events: events)
        #expect(balance.value == 10_750)
        #expect(balance.source == .reported)
        #expect(balance.asOf == at(0))
        #expect(balance.pendingCount == 2)
        #expect(balance.isEstimated)
        let historyValues: [Decimal] = balance.history.map(\.value)
        #expect(historyValues == [Decimal(10_000), Decimal(9_750), Decimal(10_750)])
    }

    @Test func latestReportedBalanceResetsAndOrderDoesNotMatter() {
        let events: [BalanceEvent] = [
            BalanceEvent(date: at(5), effect: -100, reportedBalance: 7_000),
            BalanceEvent(date: at(0), effect: -500, reportedBalance: 10_000),
            BalanceEvent(date: at(3), effect: -200),
        ]
        let balance = BalanceCalculator.balance(kind: .bankAccount, events: events)
        #expect(balance.value == 7_000)
        #expect(balance.pendingCount == 0)
        #expect(!balance.isEstimated)
    }

    @Test func transactionsBeforeAnyKnownBalanceAreIgnored() {
        let events: [BalanceEvent] = [BalanceEvent(date: at(0), effect: -500)]
        let balance = BalanceCalculator.balance(kind: .creditCard, events: events)
        #expect(balance.value == nil)
        #expect(balance.source == .none)
        #expect(balance.history.isEmpty)
    }

    @Test func manualBalanceOverridesEarlierSMS() {
        let events: [BalanceEvent] = [
            BalanceEvent(date: at(0), effect: -500, reportedBalance: 10_000),
            BalanceEvent(date: at(1), effect: 0, reportedBalance: 12_345, isManual: true),
            BalanceEvent(date: at(2), effect: -345),
        ]
        let balance = BalanceCalculator.balance(kind: .bankAccount, events: events)
        #expect(balance.value == 12_000)
        #expect(balance.source == .manual)
        #expect(balance.pendingCount == 1)
    }

    @Test func cashStartsAtZeroUntilAnOpeningBalance() {
        let spending: [BalanceEvent] = [
            BalanceEvent(date: at(1), effect: -450),
            BalanceEvent(date: at(2), effect: -50),
        ]
        let computed = BalanceCalculator.balance(kind: .cash, events: spending)
        #expect(computed.value == -500)
        #expect(computed.source == .computed)

        let withOpening = BalanceCalculator.balance(
            kind: .cash,
            events: spending + [BalanceEvent(date: at(0), effect: 0, reportedBalance: 5_000, isManual: true)]
        )
        #expect(withOpening.value == 4_500)
        #expect(withOpening.source == .manual)
    }

    @Test func creditCardOwedAndUtilization() {
        // Decimal(string:) — float literals like 52_136.34 aren't exact as Decimal.
        let available = Decimal(string: "52136.34") ?? 0
        let spent = Decimal(string: "4452.56") ?? 0
        let events: [BalanceEvent] = [BalanceEvent(date: at(0), effect: -spent, reportedBalance: available)]
        let card = BalanceCalculator.balance(kind: .creditCard, events: events, creditLimit: 100_000)
        #expect(card.value == Decimal(string: "52136.34"))
        #expect(card.amountOwed == Decimal(string: "47863.66"))
        #expect(abs((card.utilization ?? 0) - 0.4786366) < 0.0001)

        let noLimit = BalanceCalculator.balance(kind: .creditCard, events: events)
        #expect(noLimit.amountOwed == nil)
        #expect(noLimit.utilization == nil)
    }

    @Test func effectSigns() {
        #expect(BalanceEvent.effect(of: .debit, amount: 100) == -100)
        #expect(BalanceEvent.effect(of: .transfer, amount: 100) == -100)
        #expect(BalanceEvent.effect(of: .credit, amount: 100) == 100)
        #expect(BalanceEvent.effect(of: .refund, amount: 100) == 100)
        #expect(BalanceEvent.effect(of: .unknown, amount: 100) == 0)
    }

    @Test func overviewTotals() {
        let bank = BalanceCalculator.balance(kind: .bankAccount, events: [BalanceEvent(date: at(0), effect: 0, reportedBalance: 10_000)])
        let cash = BalanceCalculator.balance(kind: .cash, events: [BalanceEvent(date: at(0), effect: 0, reportedBalance: 2_000, isManual: true)])
        let card = BalanceCalculator.balance(kind: .creditCard, events: [BalanceEvent(date: at(0), effect: 0, reportedBalance: 40_000)],
                                             creditLimit: 50_000)
        let cardNoLimit = BalanceCalculator.balance(kind: .creditCard, events: [BalanceEvent(date: at(0), effect: 0, reportedBalance: 1)])
        let unknown = BalanceCalculator.balance(kind: .bankAccount, events: [])

        let overview = AccountsOverview.make([bank, cash, card, cardNoLimit, unknown])
        #expect(overview.moneyInAccounts == 12_000)
        #expect(overview.owedOnCards == 10_000)
        #expect(overview.cardsWithoutLimit == 1)
        #expect(overview.unknownBalanceCount == 1)
    }

    @Test func lowBalanceThreshold() {
        let balance = BalanceCalculator.balance(kind: .bankAccount, events: [BalanceEvent(date: at(0), effect: 0, reportedBalance: 900)])
        #expect(balance.isBelow(1_000))
        #expect(!balance.isBelow(500))
        #expect(!balance.isBelow(nil))
    }
}

// MARK: - Store + editor

@Suite("Accounts end to end")
@MainActor
struct AccountsIntegrationTests {
    let t0 = ISO8601DateFormatter().date(from: "2026-11-14T18:00:00Z") ?? .now

    let hnbCard = "HNB SMS ALERT:INTERNET, Account:1120***4821,Location:UBER EATS, LK,Amount(Approx.):570.47 LKR,Av.Bal:1,234.56 LKR,Date:14.11.26,Time:18:26, Hot Line:0112462462"
    let hnbAccount = "LKR 100.00 credited to Ac No:11202XXXXX21 on 14/11/26 16:37:48 Reason:CEFT-RELOAD Bal:LKR 681.85 Protect from scams"
    let dfccCard = "ALERT CR CARD: Livon Pharmacy CARD**3141 DEBITED LKR 4,452.56 ON (14/NOV/2026 17:46) AUTHCODE 902114 AVBAL LKR 52,136.34"

    func setUp() throws -> (ModelContainer, IngestionService, TransactionStore, TransactionEditor) {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let service = IngestionService(containerResult: .success(container))
        guard let store = service.store else { throw TestSupport.TestError.noStore }
        return (container, service, store, TransactionEditor(context: container.mainContext))
    }

    func account(named bank: String, in container: ModelContainer) throws -> Account {
        let all = try container.mainContext.fetch(FetchDescriptor<Account>())
        return try #require(all.first { $0.bankName == bank })
    }

    @Test func kindsAreDetectedAtIngest() async throws {
        let (_, service, store, _) = try setUp()
        _ = await service.ingest(body: dfccCard, sender: "DFCC", receivedAt: t0)
        let card = try #require(try await store.accountSnapshots().first)
        #expect(card.kind == .creditCard)
        #expect(card.balance.value == Decimal(string: "52136.34"))
        #expect(card.balance.source == .reported)
    }

    @Test func hnbCardThenAccountSMSBecomesOneBankAccount() async throws {
        let (_, service, store, _) = try setUp()
        _ = await service.ingest(body: hnbAccount, sender: "HNB", receivedAt: t0)
        _ = await service.ingest(body: hnbCard, sender: "HNB", receivedAt: t0)
        let accounts = try await store.accountSnapshots()
        #expect(accounts.count == 1)
        #expect(accounts.first?.kind == .bankAccount)
        #expect(accounts.first?.last4 == "4821")
        // The card alert at 18:26 is the latest reported balance.
        #expect(accounts.first?.balance.value == Decimal(string: "1234.56"))
    }

    @Test func userChosenKindIsKept() async throws {
        let (container, service, store, editor) = try setUp()
        _ = await service.ingest(body: hnbCard, sender: "HNB", receivedAt: t0)
        let hnb = try account(named: "HNB", in: container)
        try editor.updateAccount(hnb, name: "HNB Salary", kind: .creditCard, creditLimit: 10_000,
                                 lowBalanceThreshold: nil, isHidden: false)
        _ = await service.ingest(body: hnbAccount, sender: "HNB", receivedAt: t0)
        let snapshot = try #require(try await store.accountSnapshots().first)
        #expect(snapshot.kind == .creditCard)
        #expect(snapshot.displayName == "HNB Salary")
    }

    @Test func setBalanceThenTransactionsAdjustIt() async throws {
        let (container, service, store, editor) = try setUp()
        _ = await service.ingest(body: "Txn of LKR 850.00 at PICKME FOOD using card **9012 approved.", sender: nil, receivedAt: t0)
        let account = try #require(try container.mainContext.fetch(FetchDescriptor<Account>()).first)
        #expect(account.balance.value == nil) // no SMS balance yet

        try editor.setBalance(account, to: 20_000, at: t0.addingTimeInterval(60))
        _ = await service.ingest(body: "Txn of LKR 500.00 at KFC using card **9012 approved.", sender: nil,
                                 receivedAt: t0.addingTimeInterval(3_600))
        let snapshot = try #require(try await store.accountSnapshots().first)
        #expect(snapshot.balance.value == 19_500)
        #expect(snapshot.balance.source == .manual)
        #expect(snapshot.balance.pendingCount == 1)

        try editor.clearManualBalance(account)
        #expect(account.balance.value == nil)
    }

    @Test func cashAccountTracksManualEntries() throws {
        let (_, _, _, editor) = try setUp()
        let lunch = try editor.addManual(TransactionDraft(amount: 450, merchant: "Lunch", occurredAt: t0))
        let cash = try #require(lunch.account)
        #expect(cash.kind == .cash)
        try editor.setBalance(cash, to: 5_000, at: t0.addingTimeInterval(-60))
        #expect(cash.balance.value == 4_550)
    }

    @Test func mergeMovesTransactionsAndRoutesFutureSMS() async throws {
        let (container, service, store, editor) = try setUp()
        _ = await service.ingest(body: dfccCard, sender: "DFCC", receivedAt: t0)
        _ = await service.ingest(body: "Txn of LKR 850.00 at PICKME FOOD using card **9012 approved.", sender: "SOMEBANK",
                                 receivedAt: t0)
        let dfcc = try account(named: "DFCC", in: container)
        let other = try account(named: "Bank C", in: container)

        try editor.merge(other, into: dfcc)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Account>()) == 1)
        #expect(dfcc.transactions.count == 2)
        #expect(dfcc.mergedKeys == ["Bank C|9012"])

        // A later SMS for the merged card lands in the DFCC account, not a new one.
        _ = await service.ingest(body: "Txn of LKR 300.00 at KFC using card **9012 approved.", sender: "SOMEBANK",
                                 receivedAt: t0.addingTimeInterval(3_600))
        let accounts = try await store.accountSnapshots()
        #expect(accounts.count == 1)
        #expect(accounts.first?.transactionCount == 3)

        #expect(throws: EditorError.cannotMergeIntoItself) { try editor.merge(dfcc, into: dfcc) }
    }

    @Test func dedupHonoursMergedAccounts() async throws {
        let (container, service, store, editor) = try setUp()
        _ = await service.ingest(body: dfccCard, sender: "DFCC", receivedAt: t0)
        _ = await service.ingest(body: "Txn of LKR 850.00 at PICKME FOOD using card **9012 approved.", sender: nil,
                                 receivedAt: t0)
        try editor.merge(try account(named: "Bank C", in: container), into: try account(named: "DFCC", in: container))

        // Same amount on the merged card 1 minute later, worded differently → duplicate.
        let again = await service.ingest(body: "Txn of LKR 850.00 at PICKME FOOD using card **9012 approved. Ref 2",
                                         sender: nil, receivedAt: t0.addingTimeInterval(60))
        #expect(again.status == .duplicate)
        #expect(try await store.transactionSnapshots().count == 2)
    }

    @Test func accountEditValidation() async throws {
        let (container, service, _, editor) = try setUp()
        _ = await service.ingest(body: dfccCard, sender: "DFCC", receivedAt: t0)
        let dfcc = try account(named: "DFCC", in: container)
        #expect(throws: EditorError.emptyName) {
            try editor.updateAccount(dfcc, name: " ", kind: .creditCard, creditLimit: nil, lowBalanceThreshold: nil, isHidden: false)
        }
        #expect(throws: EditorError.invalidCreditLimit) {
            try editor.updateAccount(dfcc, name: "DFCC Card", kind: .creditCard, creditLimit: 0, lowBalanceThreshold: nil, isHidden: false)
        }
        try editor.updateAccount(dfcc, name: "DFCC Card", kind: .creditCard, creditLimit: 100_000,
                                 lowBalanceThreshold: 10_000, isHidden: true)
        #expect(dfcc.balance.amountOwed == Decimal(string: "47863.66"))
        #expect(dfcc.isHidden)
        #expect(!dfcc.balance.isBelow(dfcc.lowBalanceThreshold))
    }

    @Test func prepareMarksLegacyCashAccount() async throws {
        let (container, service, store, _) = try setUp()
        container.mainContext.insert(Account(bankName: TransactionEditor.cashAccountName, last4: nil, displayName: "Cash"))
        try container.mainContext.save()
        await service.prepare()
        #expect(try await store.accountSnapshots().first?.kind == .cash)
    }
}
