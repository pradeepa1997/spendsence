import SpendCore
import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = AppRouter.shared

    @AppStorage(OnboardingState.completedKey) private var onboardingCompleted = false
    /// Becomes true once we've checked whether an existing user can skip onboarding.
    @State private var onboardingChecked = false

    /// Low confidence (below `ParsingPipeline.autoAcceptThreshold`, 0.75) and not yet approved or edited.
    @Query(filter: #Predicate<SpendCore.Transaction> { $0.confidence < 0.75 && $0.isReviewed == false })
    private var awaitingReview: [SpendCore.Transaction]

    @Query(filter: #Predicate<RawMessage> { $0.statusRaw == "needsReview" })
    private var reviewMessages: [RawMessage]

    private var reviewCount: Int {
        awaitingReview.count + reviewMessages.filter { $0.transaction == nil }.count
    }

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack { DashboardView() }
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }
                .tag(AppRouter.Tab.dashboard)
            NavigationStack { TransactionListView() }
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
                .tag(AppRouter.Tab.transactions)
            NavigationStack { ReviewQueueView() }
                .tabItem { Label("Review", systemImage: "checkmark.circle") }
                .badge(reviewCount)
                .tag(AppRouter.Tab.review)
            NavigationStack { MoreView() }
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(AppRouter.Tab.more)
        }
        .onOpenURL { router.handle($0) }
        .sheet(item: $router.linkedTransaction) { link in
            NavigationStack { LinkedTransactionView(link: link) }
        }
        .sheet(isPresented: $router.showAddTransaction) {
            NavigationStack { TransactionFormView(mode: .add(linking: nil)) }
        }
        .sheet(isPresented: $router.showBudgets) {
            NavigationStack {
                BudgetsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { router.showBudgets = false }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { onboardingChecked && !onboardingCompleted },
            set: { presented in if !presented { onboardingCompleted = true } }
        )) {
            OnboardingView { onboardingCompleted = true }
        }
        .task {
            // Existing users whose automation already delivers SMS don't need the guide.
            if !onboardingCompleted, await IngestionService.shared.latestAutomationMessage() != nil {
                onboardingCompleted = true
            }
            onboardingChecked = true
        }
        .task(id: scenePhase) {
            switch scenePhase {
            case .active:
                // Seed categories, categorise older transactions, purge ignored messages older than 7 days.
                await IngestionService.shared.prepare()
            case .background:
                // Edits made in the app: refresh widgets, send any budget alert now due.
                await NotificationService.checkBudgets()
                WidgetReloader.reload()
            default:
                break
            }
        }
    }
}
