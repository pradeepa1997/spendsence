import Foundation

public struct CategorySeed: Sendable, Equatable {
    public let key: String
    public let name: String
    public let symbol: String
    public let colorHex: String
    public let excludedFromSpending: Bool
}

/// The categories every store starts with. `key` is stable; names can be changed by the user.
public enum DefaultCategories {
    public static let groceries = "groceries"
    public static let dining = "dining"
    public static let transport = "transport"
    public static let bills = "bills"
    public static let shopping = "shopping"
    public static let health = "health"
    public static let entertainment = "entertainment"
    public static let travel = "travel"
    public static let education = "education"
    public static let fees = "fees"
    public static let transfers = "transfers"
    public static let income = "income"
    public static let other = "other"

    public static let all: [CategorySeed] = [
        CategorySeed(key: groceries, name: "Groceries", symbol: "cart.fill", colorHex: "#34C759", excludedFromSpending: false),
        CategorySeed(key: dining, name: "Dining", symbol: "fork.knife", colorHex: "#FF9500", excludedFromSpending: false),
        CategorySeed(key: transport, name: "Transport", symbol: "car.fill", colorHex: "#007AFF", excludedFromSpending: false),
        CategorySeed(key: bills, name: "Bills & Utilities", symbol: "bolt.fill", colorHex: "#FFCC00", excludedFromSpending: false),
        CategorySeed(key: shopping, name: "Shopping", symbol: "bag.fill", colorHex: "#AF52DE", excludedFromSpending: false),
        CategorySeed(key: health, name: "Health", symbol: "cross.case.fill", colorHex: "#FF3B30", excludedFromSpending: false),
        CategorySeed(key: entertainment, name: "Entertainment", symbol: "tv.fill", colorHex: "#FF2D55", excludedFromSpending: false),
        CategorySeed(key: travel, name: "Travel", symbol: "airplane", colorHex: "#5AC8FA", excludedFromSpending: false),
        CategorySeed(key: education, name: "Education", symbol: "book.fill", colorHex: "#5856D6", excludedFromSpending: false),
        CategorySeed(key: fees, name: "Fees & Charges", symbol: "building.columns.fill", colorHex: "#8E8E93", excludedFromSpending: false),
        CategorySeed(key: transfers, name: "Transfers", symbol: "arrow.left.arrow.right", colorHex: "#A2845E", excludedFromSpending: true),
        CategorySeed(key: income, name: "Income", symbol: "arrow.down.circle.fill", colorHex: "#30B0C7", excludedFromSpending: false),
        CategorySeed(key: other, name: "Other", symbol: "square.grid.2x2.fill", colorHex: "#636366", excludedFromSpending: false),
    ]
}
