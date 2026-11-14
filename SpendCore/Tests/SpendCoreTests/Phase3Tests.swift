import Foundation
import SwiftData
import Testing
@testable import SpendCore

@Suite("Budgets")
struct BudgetTests {
    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso) ?? .distantPast }

    func status(spent: Decimal, budget: Decimal, name: String = "Dining", id: UUID = UUID()) -> BudgetStatus {
        BudgetStatus(categoryID: id, name: name, symbol: "fork.knife", colorHex: "#FF9500", budget: budget, spent: spent)
    }

    @Test func levelsAndRemaining() {
        #expect(status(spent: 7_900, budget: 10_000).level == .ok)
        #expect(status(spent: 8_000, budget: 10_000).level == .warning)
        #expect(status(spent: 10_000, budget: 10_000).level == .over)
        #expect(status(spent: 12_500, budget: 10_000).remaining == -2_500)
        #expect(status(spent: 2_500, budget: 10_000).fraction == 0.25)
        #expect(BudgetStatus.Level.over > BudgetStatus.Level.warning)
    }

    @Test func statusesFromSummary() {
        let dining = UUID()
        let groceries = UUID()
        let transport = UUID()
        let facts: [TransactionFact] = [
            TransactionFact(amount: 9_000, type: .debit, occurredAt: date("2026-11-03T10:00:00Z"),
                            categoryID: dining, categoryName: "Dining"),
            TransactionFact(amount: 4_000, type: .debit, occurredAt: date("2026-11-04T10:00:00Z"),
                            categoryID: groceries, categoryName: "Groceries"),
        ]
        let november = SpendingSummary.month(containing: date("2026-11-15T00:00:00Z"), calendar: utc)
        let summary = SpendingSummary.make(facts: facts, interval: november, calendar: utc)
        let budgets: [BudgetInput] = [
            BudgetInput(categoryID: groceries, name: "Groceries", symbol: "cart.fill", colorHex: "#34C759", budget: 20_000),
            BudgetInput(categoryID: dining, name: "Dining", symbol: "fork.knife", colorHex: "#FF9500", budget: 10_000),
            BudgetInput(categoryID: transport, name: "Transport", symbol: "car.fill", colorHex: "#007AFF", budget: 5_000),
        ]
        let statuses = BudgetCalculator.statuses(summary: summary, budgets: budgets)
        #expect(statuses.map(\.name) == ["Dining", "Groceries", "Transport"])
        let spent: [Decimal] = statuses.map(\.spent)
        #expect(spent == [Decimal(9_000), Decimal(4_000), Decimal(0)])
        #expect(statuses.first?.level == .warning)

        let overall = BudgetCalculator.overall(statuses)
        #expect(overall?.spent == 13_000)
        #expect(overall?.budget == 35_000)
        #expect(BudgetCalculator.overall([]) == nil)
    }

    @Test func alertsOncePerThresholdPerMonth() {
        let id = UUID()
        let month = "2026-11"
        let warning = status(spent: 8_500, budget: 10_000, id: id)

        let first = BudgetAlertPlanner.alerts(for: [warning], monthKey: month, alreadySent: [])
        #expect(first.map(\.threshold) == [80])

        let sent = Set(first.flatMap(\.keys))
        #expect(BudgetAlertPlanner.alerts(for: [warning], monthKey: month, alreadySent: sent).isEmpty)

        let over = status(spent: 10_200, budget: 10_000, id: id)
        let second = BudgetAlertPlanner.alerts(for: [over], monthKey: month, alreadySent: sent)
        #expect(second.map(\.threshold) == [100])

        // A new month starts fresh.
        #expect(BudgetAlertPlanner.alerts(for: [warning], monthKey: "2026-12", alreadySent: sent).count == 1)
    }

    @Test func jumpingPastHundredSendsOnlyTheHundredAlert() {
        let id = UUID()
        let alerts = BudgetAlertPlanner.alerts(for: [status(spent: 15_000, budget: 10_000, id: id)],
                                               monthKey: "2026-11", alreadySent: [])
        #expect(alerts.count == 1)
        #expect(alerts.first?.threshold == 100)
        #expect(alerts.first?.keys.count == 2) // 80% is marked as sent too
    }

    @Test func noAlertBelowEightyPercent() {
        #expect(BudgetAlertPlanner.alerts(for: [status(spent: 100, budget: 10_000)], monthKey: "2026-11", alreadySent: []).isEmpty)
    }

    @Test func monthKeysAndPruning() {
        #expect(BudgetAlertPlanner.monthKey(for: date("2026-11-30T23:00:00Z"), calendar: utc) == "2026-11")
        #expect(BudgetAlertPlanner.monthKey(for: date("2027-01-01T00:00:00Z"), calendar: utc) == "2027-01")
        let id = UUID()
        let sent: Set<String> = [
            BudgetAlertPlanner.key(monthKey: "2026-10", categoryID: id, threshold: 80),
            BudgetAlertPlanner.key(monthKey: "2026-11", categoryID: id, threshold: 80),
        ]
        #expect(BudgetAlertPlanner.pruned(sent, keepingMonth: "2026-11").count == 1)
    }
}

@Suite("Compact amounts")
struct CompactAmountTests {
    @Test(arguments: [
        ("950", "LKR 950"),
        ("2450.75", "LKR 2,451"),
        ("45320", "LKR 45.3K"),
        ("1250000", "LKR 1.25M"),
    ])
    func formats(input: String, expected: String) {
        let amount = Decimal(string: input, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        #expect(AmountFormatter.compact(amount, currency: "LKR") == expected)
    }

    @Test func withoutCurrency() {
        #expect(AmountFormatter.compact(45_320, currency: "") == "45.3K")
    }
}

@Suite("Phase 3 store")
@MainActor
struct Phase3StoreTests {
    let t0 = ISO8601DateFormatter().date(from: "2026-11-14T18:00:00Z") ?? .now

    func setUp() throws -> (ModelContainer, IngestionService, TransactionStore, TransactionEditor) {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let service = IngestionService(containerResult: .success(container))
        guard let store = service.store else { throw TestSupport.TestError.noStore }
        return (container, service, store, TransactionEditor(context: container.mainContext))
    }

    @Test func dashboardSnapshotIncludesBudgetsAndReviewCount() async throws {
        let (container, service, _, editor) = try setUp()
        _ = await service.addExpense(amount: 9_000, merchant: "Dinner", categoryName: "Dining", occurredAt: t0)
        _ = await service.ingest(body: "LKR 1,500.00 at SPAR KIRULAPONE card ending 7788", sender: "BANKD", receivedAt: t0)

        let dining = try #require(try CategoryService.ensureDefaultCategories(in: container.mainContext)
            .first { $0.systemKey == DefaultCategories.dining })
        try editor.setBudget(dining, to: 10_000)

        let snapshot = try #require(await service.dashboardSnapshot(now: t0))
        #expect(snapshot.summary.totalSpent == 10_500)
        #expect(snapshot.awaitingReview == 1)
        #expect(snapshot.budgets.count == 1)
        #expect(snapshot.budgets.first?.level == .warning)
        #expect(snapshot.overallBudgetFraction == 0.9)

        #expect(throws: EditorError.invalidBudget) { try editor.setBudget(dining, to: 0) }
        try editor.setBudget(dining, to: nil)
        #expect(try #require(await service.dashboardSnapshot(now: t0)).budgets.isEmpty)
    }

    @Test func notAnExpenseByID() async throws {
        let (_, service, store, _) = try setUp()
        let result = await service.ingest(
            body: "ALERT CR CARD: Livon Pharmacy CARD**3141 DEBITED LKR 4,452.56 ON (14/NOV/2026 17:46) AUTHCODE 902114",
            sender: "DFCC", receivedAt: t0
        )
        let id = try #require(result.transactionID)
        #expect(await service.transaction(id: id)?.merchant == "Livon Pharmacy")

        #expect(await service.markNotATransaction(id: id))
        #expect(await service.transaction(id: id) == nil)
        #expect(try await store.rawMessageSnapshots().first?.status == .ignored)
        #expect(await service.markNotATransaction(id: id) == false)
    }
}
