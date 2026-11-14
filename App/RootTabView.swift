import SpendCore
import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase

    @Query(QueryDescriptors.awaitingReview)
    private var awaitingReview: [SpendCore.Transaction]

    @Query(filter: #Predicate<RawMessage> { $0.statusRaw == "needsReview" })
    private var reviewMessages: [RawMessage]

    private var reviewCount: Int {
        awaitingReview.count + reviewMessages.filter { $0.transaction == nil }.count
    }

    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }
            NavigationStack { TransactionListView() }
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
            NavigationStack { ReviewQueueView() }
                .tabItem { Label("Review", systemImage: "checkmark.circle") }
                .badge(reviewCount)
            NavigationStack { MoreView() }
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .task(id: scenePhase) {
            // Seed categories, categorise older transactions, purge ignored messages older than 7 days.
            guard scenePhase == .active else { return }
            await IngestionService.shared.prepare()
        }
    }
}
