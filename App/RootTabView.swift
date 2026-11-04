import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Text("Transactions")
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
            Text("Messages")
                .tabItem { Label("Messages", systemImage: "message") }
            Text("Simulate")
                .tabItem { Label("Simulate", systemImage: "hammer") }
        }
    }
}
