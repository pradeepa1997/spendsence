import SpendCore
import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TransactionListView()
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
            RawMessageListView()
                .tabItem { Label("Messages", systemImage: "message") }
            SimulateSMSView()
                .tabItem { Label("Simulate", systemImage: "hammer") }
        }
        .task(id: scenePhase) {
            // Each time the app becomes active, drop ignored messages (OTPs, promos) older than 7 days.
            guard scenePhase == .active else { return }
            await IngestionService.shared.purgeExpiredIgnoredMessages()
        }
    }
}
