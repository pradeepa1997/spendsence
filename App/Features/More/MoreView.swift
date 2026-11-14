import SwiftUI
import SpendCore

struct MoreView: View {
    var body: some View {
        List {
            Section("Organize") {
                NavigationLink {
                    AccountsView()
                } label: {
                    Label("Accounts & balances", systemImage: "building.columns")
                }
                NavigationLink {
                    BudgetsView()
                } label: {
                    Label("Budgets", systemImage: "gauge.with.dots.needle.33percent")
                }
                NavigationLink {
                    CategoriesView()
                } label: {
                    Label("Categories", systemImage: "square.grid.2x2")
                }
                NavigationLink {
                    MerchantRulesView()
                } label: {
                    Label("Merchant rules", systemImage: "wand.and.stars")
                }
            }

            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }

            Section("Debug") {
                NavigationLink {
                    RawMessageListView()
                } label: {
                    Label("Messages", systemImage: "message")
                }
                NavigationLink {
                    SimulateSMSView()
                } label: {
                    Label("Simulate SMS", systemImage: "hammer")
                }
            }

            Section("About") {
                LabeledContent("Parser version", value: "\(ParsingPipeline.version)")
                LabeledContent("Data", value: "Stored only on this iPhone")
            }
        }
        .navigationTitle("More")
    }
}
