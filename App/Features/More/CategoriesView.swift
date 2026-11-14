import SwiftData
import SwiftUI
import SpendCore

struct CategoriesView: View {
    enum EditTarget: Identifiable {
        case new
        case existing(TransactionCategory)

        var id: String {
            switch self {
            case .new: "new"
            case .existing(let category): category.id.uuidString
            }
        }
    }

    @Environment(\.modelContext) private var context

    @Query(sort: \TransactionCategory.sortOrder)
    private var categories: [TransactionCategory]

    @State private var editing: EditTarget?
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    Button {
                        editing = .existing(category)
                    } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(category: category)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name)
                                    .foregroundStyle(.primary)
                                if category.excludedFromSpending {
                                    Text("Not counted as spending")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(category.transactions.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        if !category.isSystem {
                            Button(role: .destructive) {
                                do {
                                    try TransactionEditor(context: context).deleteCategory(category)
                                } catch {
                                    errorText = error.localizedDescription
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } footer: {
                Text("Built-in categories can be renamed and restyled. Deleting your own category moves its transactions to Other.")
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            Button {
                editing = .new
            } label: {
                Label("Add category", systemImage: "plus")
            }
        }
        .sheet(item: $editing) { target in
            NavigationStack {
                CategoryEditorView(target: target)
            }
        }
        .errorAlert($errorText)
    }
}

struct CategoryEditorView: View {
    static let symbols = [
        "cart.fill", "fork.knife", "car.fill", "bolt.fill", "bag.fill", "cross.case.fill",
        "tv.fill", "airplane", "book.fill", "building.columns.fill", "arrow.left.arrow.right", "arrow.down.circle.fill",
        "square.grid.2x2.fill", "house.fill", "pawprint.fill", "gift.fill", "heart.fill", "figure.run",
        "gamecontroller.fill", "wrench.and.screwdriver.fill", "tshirt.fill", "graduationcap.fill", "phone.fill",
        "drop.fill", "leaf.fill", "creditcard.fill", "banknote.fill", "person.2.fill", "fuelpump.fill", "cup.and.saucer.fill",
    ]

    static let colors = [
        "#34C759", "#FF9500", "#007AFF", "#FFCC00", "#AF52DE", "#FF3B30", "#FF2D55",
        "#5AC8FA", "#5856D6", "#8E8E93", "#A2845E", "#30B0C7", "#636366", "#00C7BE",
    ]

    let target: CategoriesView.EditTarget

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var symbol: String
    @State private var colorHex: String
    @State private var errorText: String?

    init(target: CategoriesView.EditTarget) {
        self.target = target
        switch target {
        case .new:
            _name = State(initialValue: "")
            _symbol = State(initialValue: "square.grid.2x2.fill")
            _colorHex = State(initialValue: "#007AFF")
        case .existing(let category):
            _name = State(initialValue: category.name)
            _symbol = State(initialValue: category.symbol)
            _colorHex = State(initialValue: category.colorHex)
        }
    }

    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    CategoryIconView(symbol: symbol, colorHex: colorHex, size: 64)
                    Spacer()
                }
                TextField("Name", text: $name)
            }

            Section("Icon") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Self.symbols, id: \.self) { candidate in
                        Button {
                            symbol = candidate
                        } label: {
                            Image(systemName: candidate)
                                .frame(width: 40, height: 40)
                                .background(
                                    symbol == candidate ? Color(hex: colorHex).opacity(0.25) : Color.clear,
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Colour") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Self.colors, id: \.self) { hex in
                        Button {
                            colorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if colorHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(isNew ? "New category" : "Edit category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .errorAlert($errorText)
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private func save() {
        let editor = TransactionEditor(context: context)
        do {
            switch target {
            case .new:
                try editor.addCategory(name: name, symbol: symbol, colorHex: colorHex)
            case .existing(let category):
                try editor.updateCategory(category, name: name, symbol: symbol, colorHex: colorHex)
            }
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
