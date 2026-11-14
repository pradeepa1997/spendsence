import SwiftData
import SwiftUI
import SpendCore

struct CategoryPicker: View {
    @Binding var selection: UUID?

    @Query(sort: \TransactionCategory.sortOrder)
    private var categories: [TransactionCategory]

    var body: some View {
        Picker("Category", selection: $selection) {
            Text("None").tag(UUID?.none)
            ForEach(categories) { category in
                Label(category.name, systemImage: category.symbol)
                    .tag(Optional(category.id))
            }
        }
    }
}
