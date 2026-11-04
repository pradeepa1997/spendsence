import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TransactionListView()
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
            RawMessageListView()
                .tabItem { Label("Messages", systemImage: "message") }
            SimulateSMSView()
                .tabItem { Label("Simulate", systemImage: "hammer") }
        }
    }
}
