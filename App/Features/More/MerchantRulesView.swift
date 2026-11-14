import SwiftData
import SwiftUI
import SpendCore

/// Rules the user taught by editing transactions ("Remember for future messages").
struct MerchantRulesView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \MerchantRule.pattern)
    private var rules: [MerchantRule]

    @State private var errorText: String?

    var body: some View {
        Group {
            if rules.isEmpty {
                ContentUnavailableView(
                    "No merchant rules yet",
                    systemImage: "wand.and.stars",
                    description: Text("Edit a transaction's merchant name or category and choose “Remember” to teach the app.")
                )
            } else {
                List {
                    Section {
                        ForEach(rules) { rule in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.pattern)
                                    .font(.subheadline.monospaced())
                                if let renameTo = rule.renameTo {
                                    Label("Show as “\(renameTo)”", systemImage: "character.cursor.ibeam")
                                        .font(.caption)
                                }
                                if let category = rule.category {
                                    Label("File under \(category.name)", systemImage: category.symbol)
                                        .font(.caption)
                                }
                                Text(rule.hitCount == 1 ? "Applied once" : "Applied \(rule.hitCount) times")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    do {
                                        try TransactionEditor(context: context).deleteRule(rule)
                                    } catch {
                                        errorText = error.localizedDescription
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("Rules apply to new SMS whose merchant contains these words. Deleting a rule doesn't change past transactions.")
                    }
                }
            }
        }
        .navigationTitle("Merchant rules")
        .errorAlert($errorText)
    }
}
