import Foundation
import SwiftData
import Testing
@testable import SpendCore

// MARK: - Pure categorisation

@Suite("Merchant keys")
struct MerchantKeyTests {
    @Test(arguments: [
        ("Uber Eats, LK", "UBER EATS LK"),
        ("NETFLIX.COM", "NETFLIX COM"),
        ("  Keells Super - Nugegoda ", "KEELLS SUPER NUGEGODA"),
        ("McDonald's", "MCDONALD S"),
    ])
    func normalizes(input: String, expected: String) {
        #expect(MerchantKey.make(input) == expected)
    }

    @Test func emptyIsNil() {
        #expect(MerchantKey.make(nil) == nil)
        #expect(MerchantKey.make(" - ") == nil)
    }

    @Test func matchesWholeWordsOnly() {
        #expect(MerchantKey.matches("UBER TRIP", pattern: "UBER"))
        #expect(!MerchantKey.matches("UBERX", pattern: "UBER"))
        #expect(!MerchantKey.matches("SPARK MOTORS", pattern: "SPAR"))
        #expect(MerchantKey.matches("CARGILLS FOOD CITY", pattern: "FOOD CITY"))
        #expect(!MerchantKey.matches("ANYTHING", pattern: ""))
    }
}

@Suite("Categorizer")
struct CategorizerTests {
    @Test(arguments: [
        ("Uber Eats", DefaultCategories.dining),
        ("Uber Trip", DefaultCategories.transport),
        ("Pickme Food", DefaultCategories.dining),
        ("Keells Super - Nugegoda", DefaultCategories.groceries),
        ("Cargills Food City", DefaultCategories.groceries),
        ("Livon Pharmacy", DefaultCategories.health),
        ("Java Lounge PVT LTD Piliyan", DefaultCategories.dining),
        ("ATM Charges Refund", DefaultCategories.fees),
        ("ATM Withdrawal", DefaultCategories.transfers),
        ("Outward Ceft Transfer", DefaultCategories.transfers),
        ("Lpay TFR", DefaultCategories.transfers),
        ("Netflix.com", DefaultCategories.entertainment),
        ("Dialog Axiata", DefaultCategories.bills),
        ("Daraz LK", DefaultCategories.shopping),
        ("Cibmart Piliyandala", DefaultCategories.other),
    ])
    func keywordMapForDebits(merchant: String, expected: String) {
        #expect(Categorizer.choose(merchant: merchant, type: .debit, rules: []) == .system(expected))
    }

    @Test func creditsAreIncomeAndTransfersAreTransfers() {
        #expect(Categorizer.choose(merchant: "Ceft-reload", type: .credit, rules: []) == .system(DefaultCategories.income))
        #expect(Categorizer.choose(merchant: nil, type: .credit, rules: []) == .system(DefaultCategories.income))
        #expect(Categorizer.choose(merchant: "X", type: .transfer, rules: []) == .system(DefaultCategories.transfers))
        #expect(Categorizer.choose(merchant: nil, type: .debit, rules: []) == .system(DefaultCategories.other))
    }

    @Test func refundsUseTheMerchantsCategory() {
        #expect(Categorizer.choose(merchant: "Daraz LK", type: .refund, rules: []) == .system(DefaultCategories.shopping))
    }

    @Test func rulesBeatKeywordsAndCreditDefaults() {
        let groceries = UUID()
        let rules = [RuleCandidate(pattern: "UBER EATS", categoryID: groceries)]
        #expect(Categorizer.choose(merchant: "Uber Eats", type: .debit, rules: rules) == .category(groceries))
        #expect(Categorizer.choose(merchant: "Uber Eats", type: .credit, rules: rules) == .category(groceries))
    }

    @Test func renameOnlyRulesDontAffectCategory() {
        let rules = [RuleCandidate(pattern: "UBER EATS", categoryID: nil, renameTo: "Uber Eats")]
        #expect(Categorizer.choose(merchant: "Uber Eats", type: .debit, rules: rules) == .system(DefaultCategories.dining))
    }

    @Test func exactThenLongestRuleWins() {
        let short = RuleCandidate(pattern: "UBER", categoryID: UUID())
        let long = RuleCandidate(pattern: "UBER EATS", categoryID: UUID())
        let exact = RuleCandidate(pattern: "UBER EATS LK", categoryID: UUID())
        #expect(Categorizer.matchingRule(for: "UBER EATS COLOMBO", in: [short, long]) == long)
        #expect(Categorizer.matchingRule(for: "UBER EATS LK", in: [short, long, exact]) == exact)
        #expect(Categorizer.matchingRule(for: "PICKME", in: [short, long]) == nil)
    }
}

// MARK: - Spending summary

@Suite("Spending summary")
struct SpendingSummaryTests {
    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso) ?? .distantPast
    }

    @Test func totalsByCategoryDayAndMerchant() throws {
        let dining = UUID()
        let groceries = UUID()
        let transfers = UUID()
        let facts: [TransactionFact] = [
            TransactionFact(amount: 1_000, type: .debit, occurredAt: date("2026-11-02T10:00:00Z"), merchant: "Uber Eats",
                            categoryID: dining, categoryName: "Dining"),
            TransactionFact(amount: 500, type: .debit, occurredAt: date("2026-11-02T12:00:00Z"), merchant: "Uber Eats",
                            categoryID: dining, categoryName: "Dining"),
            TransactionFact(amount: 3_000, type: .debit, occurredAt: date("2026-11-05T09:00:00Z"), merchant: "Keells",
                            categoryID: groceries, categoryName: "Groceries"),
            TransactionFact(amount: 200, type: .refund, occurredAt: date("2026-11-06T09:00:00Z"), merchant: "Keells",
                            categoryID: groceries, categoryName: "Groceries"),
            TransactionFact(amount: 20_000, type: .debit, occurredAt: date("2026-11-07T09:00:00Z"), merchant: "ATM",
                            categoryID: transfers, categoryName: "Transfers", excludedFromSpending: true),
            TransactionFact(amount: 150_000, type: .credit, occurredAt: date("2026-11-25T09:00:00Z"), categoryName: "Income"),
            TransactionFact(amount: 45, currency: "USD", type: .debit, occurredAt: date("2026-11-08T09:00:00Z")),
            TransactionFact(amount: 9_999, type: .debit, occurredAt: date("2026-10-31T23:59:00Z")), // previous month
        ]
        let november = SpendingSummary.month(containing: date("2026-11-15T00:00:00Z"), calendar: utc)
        let summary = SpendingSummary.make(facts: facts, interval: november, calendar: utc)

        #expect(summary.totalSpent == 4_300)
        #expect(summary.totalIncome == 150_000)
        #expect(summary.net == 145_700)
        #expect(summary.byCategory.map(\.name) == ["Groceries", "Dining"])
        let categoryAmounts: [Decimal] = summary.byCategory.map(\.amount)
        #expect(categoryAmounts == [Decimal(2_800), Decimal(1_500)])
        #expect(summary.byDay.count == 30)
        #expect(summary.byDay[1].amount == 1_500) // 2 Nov
        #expect(summary.byDay[5].amount == -200)  // 6 Nov: refund only
        #expect(summary.topMerchants.map(\.name) == ["Keells", "Uber Eats"])
        #expect(summary.topMerchants.first?.count == 2)
        #expect(summary.transactionCount == 6)
        #expect(summary.otherCurrencyCount == 1)
    }

    @Test func emptyMonth() {
        let november = SpendingSummary.month(containing: date("2026-11-15T00:00:00Z"), calendar: utc)
        let summary = SpendingSummary.make(facts: [], interval: november, calendar: utc)
        #expect(summary.totalSpent == 0)
        #expect(summary.byCategory.isEmpty)
        #expect(summary.byDay.allSatisfy { $0.amount == 0 })
    }
}

// MARK: - Store + editor

@Suite("Categories, rules and editing")
@MainActor
struct EditorTests {
    let t0 = ISO8601DateFormatter().date(from: "2026-11-14T18:00:00Z") ?? .now

    func setUp() throws -> (ModelContainer, IngestionService, TransactionStore, TransactionEditor) {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let service = IngestionService(containerResult: .success(container))
        guard let store = service.store else { throw TestSupport.TestError.noStore }
        return (container, service, store, TransactionEditor(context: container.mainContext))
    }

    func transaction(_ id: UUID?, in container: ModelContainer) throws -> SpendCore.Transaction {
        let all = try container.mainContext.fetch(FetchDescriptor<SpendCore.Transaction>())
        return try #require(all.first { $0.id == id })
    }

    @Test func defaultCategoriesSeedOnceInOrder() async throws {
        let (container, service, store, _) = try setUp()
        await service.prepare()
        await service.prepare()
        #expect(try await store.categoryNames() == DefaultCategories.all.map(\.name))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<TransactionCategory>()) == 13)
    }

    @Test func ingestAssignsCategoryFromKeywords() async throws {
        let (_, service, store, _) = try setUp()
        _ = await service.ingest(
            body: "ALERT CR CARD: Livon Pharmacy CARD**3141 DEBITED LKR 4,452.56 ON (14/NOV/2026 17:46) AUTHCODE 902114",
            sender: "DFCC", receivedAt: t0
        )
        _ = await service.ingest(
            body: "LKR 100.00 credited to Ac No:11202XXXXX21 on 14/11/26 16:37:48 Reason:CEFT-RELOAD Bal:LKR 681.85",
            sender: "HNB", receivedAt: t0
        )
        let snapshots: [TransactionSnapshot] = try await store.transactionSnapshots()
        let pharmacy = snapshots.first { $0.merchant == "Livon Pharmacy" }
        let reload = snapshots.first { $0.merchant == "Ceft-reload" }
        #expect(pharmacy?.categorySystemKey == DefaultCategories.health)
        #expect(reload?.categorySystemKey == DefaultCategories.income)
    }

    @Test func rememberedRuleRenamesAndRecategorisesFutureAndPast() async throws {
        let (container, service, store, editor) = try setUp()
        let peoples = { (amount: String, minute: Int) in
            "Dear Sir/Madam, Your A/C 335-2001****47 has been debited by Rs. \(amount) (LPAY TFR @10:\(minute) 14/11/2026).[Av_Bal: Rs. 1045408.41]"
        }
        let first = await service.ingest(body: peoples("20025.00", 11), sender: "PeoplesBank", receivedAt: t0)
        let second = await service.ingest(body: peoples("500.00", 30), sender: "PeoplesBank", receivedAt: t0)

        // The user renames the first one and files it under Bills.
        let edited = try transaction(first.transactionID, in: container)
        let bills = try #require(try CategoryService.ensureDefaultCategories(in: container.mainContext)
            .first { $0.systemKey == DefaultCategories.bills })
        let outcome = try editor.update(edited, with: TransactionDraft(
            amount: edited.amount, type: edited.type, merchant: "LankaPay Transfer", categoryID: bills.id,
            occurredAt: edited.occurredAt
        ))
        #expect(outcome == EditOutcome(merchantKey: "LPAY TFR", merchantRenamed: true, categoryChanged: true))
        #expect(outcome.canRemember)

        let updatedPast = try editor.remember(from: edited, rename: true, category: true, applyToPast: true)
        #expect(updatedPast == 1)
        let past = try transaction(second.transactionID, in: container)
        #expect(past.merchant == "LankaPay Transfer")
        #expect(past.originalMerchant == "Lpay TFR")
        #expect(past.category?.systemKey == DefaultCategories.bills)

        // A future SMS from the same merchant picks the rule up at ingest.
        let third = await service.ingest(body: peoples("750.00", 45), sender: "PeoplesBank", receivedAt: t0)
        let future = try #require(try await store.transactionSnapshots().first { $0.id == third.transactionID })
        #expect(future.merchant == "LankaPay Transfer")
        #expect(future.originalMerchant == "Lpay TFR")
        #expect(future.categorySystemKey == DefaultCategories.bills)
        #expect(try await store.ruleCount() == 1)
        #expect(edited.isReviewed && edited.isUserEdited)
    }

    @Test func applyToPastKeepsManuallyChosenCategories() async throws {
        let (container, service, _, editor) = try setUp()
        let a = await service.ingest(body: "Txn of LKR 850.00 at CIBMART using card **9012 approved.", sender: nil, receivedAt: t0)
        let b = await service.ingest(body: "Txn of LKR 300.00 at CIBMART using card **9012 approved.", sender: nil,
                                     receivedAt: t0.addingTimeInterval(3600))
        let categories = try CategoryService.ensureDefaultCategories(in: container.mainContext)
        let groceries = try #require(categories.first { $0.systemKey == DefaultCategories.groceries })
        let shopping = try #require(categories.first { $0.systemKey == DefaultCategories.shopping })

        let manual = try transaction(b.transactionID, in: container)
        try editor.setCategory(shopping, for: manual)
        let source = try transaction(a.transactionID, in: container)
        try editor.setCategory(groceries, for: source)
        #expect(try editor.remember(from: source, rename: false, category: true, applyToPast: true) == 0)
        #expect(manual.category?.systemKey == DefaultCategories.shopping)
    }

    @Test func markNotATransactionDeletesAndIgnoresTheSMS() async throws {
        let (container, service, store, editor) = try setUp()
        let result = await service.ingest(body: "LKR 1,500.00 at SPAR KIRULAPONE card ending 7788", sender: "BANKD", receivedAt: t0)
        #expect(result.status == .needsReview)
        let item = try transaction(result.transactionID, in: container)
        #expect(item.isAwaitingReview)

        try editor.markNotATransaction(item)
        #expect(try await store.transactionSnapshots().isEmpty)
        let raw = try #require(try await store.rawMessageSnapshots().first)
        #expect(raw.status == .ignored)
        #expect(raw.failureReason == "Marked as not a transaction")
    }

    @Test func approveRemovesFromReviewQueue() async throws {
        let (container, service, _, editor) = try setUp()
        let result = await service.ingest(body: "LKR 1,500.00 at SPAR KIRULAPONE card ending 7788", sender: "BANKD", receivedAt: t0)
        let item = try transaction(result.transactionID, in: container)
        try editor.approve(item)
        #expect(!item.isAwaitingReview)
        #expect(item.needsReview)
    }

    @Test func manualEntryUsesCashAccountAndChosenCategory() throws {
        let (container, _, _, editor) = try setUp()
        let dining = try #require(try CategoryService.ensureDefaultCategories(in: container.mainContext)
            .first { $0.systemKey == DefaultCategories.dining })
        let a = try editor.addManual(TransactionDraft(amount: 450, merchant: " Lunch ", categoryID: dining.id, occurredAt: t0))
        let b = try editor.addManual(TransactionDraft(amount: 120, merchant: "PickMe", occurredAt: t0))

        #expect(a.merchant == "Lunch")
        #expect(a.source == .manual)
        #expect(a.account?.displayName == "Cash")
        #expect(a.account?.id == b.account?.id)
        #expect(a.category?.id == dining.id)
        #expect(a.categoryIsManual)
        #expect(b.category?.systemKey == DefaultCategories.transport) // auto-categorised
        #expect(!a.isAwaitingReview)
        #expect(throws: EditorError.invalidAmount) {
            try editor.addManual(TransactionDraft(amount: 0, occurredAt: t0))
        }
    }

    @Test func siriAddExpenseMatchesCategoryByName() async throws {
        let (_, service, store, _) = try setUp()
        let summary = await service.addExpense(amount: 450, merchant: "Lunch", categoryName: "dining")
        #expect(summary == "Added LKR 450.00 – Lunch (Dining)")
        let saved = try #require(try await store.transactionSnapshots().first)
        #expect(saved.source == .manual)
        #expect(saved.accountDisplayName == "Cash")
    }

    @Test func manualEntryCanResolveAnUnreadableSMS() async throws {
        let (container, service, store, editor) = try setUp()
        _ = await service.ingest(body: "Your card ending 1234 was debited. Please check the app.", sender: "BANKA", receivedAt: t0)
        let raw = try #require(try container.mainContext.fetch(FetchDescriptor<RawMessage>()).first)
        #expect(raw.status == .needsReview)

        try editor.addManual(TransactionDraft(amount: 990, merchant: "KFC", occurredAt: t0), linking: raw)
        #expect(raw.status == .parsed)
        #expect(try await store.transactionSnapshots().first?.rawMessageID == raw.id)
    }

    @Test func deletingAUserCategoryMovesTransactionsToOther() throws {
        let (container, _, _, editor) = try setUp()
        let pets = try editor.addCategory(name: "Pets", symbol: "pawprint.fill", colorHex: "#FF9500")
        let item = try editor.addManual(TransactionDraft(amount: 2_000, merchant: "Pet shop", categoryID: pets.id, occurredAt: t0))
        try editor.remember(from: item, rename: false, category: true, applyToPast: false)

        try editor.deleteCategory(pets)
        #expect(item.category?.systemKey == DefaultCategories.other)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<MerchantRule>()) == 0)

        let other = try #require(item.category)
        #expect(throws: EditorError.systemCategoryCannotBeDeleted) { try editor.deleteCategory(other) }
        #expect(throws: EditorError.emptyName) { try editor.addCategory(name: "  ", symbol: "x", colorHex: "#000000") }
    }

    @Test func prepareBackfillsUncategorizedTransactions() async throws {
        let (container, service, store, _) = try setUp()
        let context = container.mainContext
        let legacy = SpendCore.Transaction(amount: 100, type: .debit, merchant: "Keells Super", occurredAt: t0,
                                           confidence: 0.9, source: .sms)
        context.insert(legacy)
        try context.save()

        await service.prepare()
        #expect(try await store.transactionSnapshots().first?.categorySystemKey == DefaultCategories.groceries)
    }

    @Test func monthlySummaryThroughTheService() async throws {
        let (_, service, _, _) = try setUp()
        _ = await service.addExpense(amount: 450, merchant: "Lunch", categoryName: "Dining", occurredAt: t0)
        _ = await service.addExpense(amount: 50, merchant: "Bus", categoryName: "Transport", occurredAt: t0)
        let summary = try #require(await service.monthlySummary(containing: t0))
        #expect(summary.totalSpent == 500)
        #expect(summary.byCategory.first?.name == "Dining")
    }
}
