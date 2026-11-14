import Foundation
import SwiftData

/// Category seeding and resolution against a `ModelContext`. Callers save.
/// Used by `TransactionStore` (ingest, on its actor context) and `TransactionEditor` (main context).
public enum CategoryService {
    public struct Resolution {
        public let category: TransactionCategory?
        /// Display name from a matching merchant rule, if it renames.
        public let renamedMerchant: String?
        /// The merchant rule that matched (for hit counting), if any.
        public let rule: MerchantRule?
    }

    /// Inserts any default category that is missing (by `systemKey`) and returns all categories. Idempotent.
    @discardableResult
    public static func ensureDefaultCategories(in context: ModelContext) throws -> [TransactionCategory] {
        var categories = try context.fetch(FetchDescriptor<TransactionCategory>())
        let existingKeys = Set(categories.compactMap(\.systemKey))
        for (index, seed) in DefaultCategories.all.enumerated() where !existingKeys.contains(seed.key) {
            let category = TransactionCategory(
                name: seed.name,
                symbol: seed.symbol,
                colorHex: seed.colorHex,
                isSystem: true,
                systemKey: seed.key,
                sortOrder: index,
                excludedFromSpending: seed.excludedFromSpending
            )
            context.insert(category)
            categories.append(category)
        }
        return categories
    }

    public static func resolve(merchant: String?, type: TransactionType, in context: ModelContext) throws -> Resolution {
        let categories = try ensureDefaultCategories(in: context)
        let rules = try context.fetch(FetchDescriptor<MerchantRule>())
        let candidates = rules.map {
            RuleCandidate(id: $0.id, pattern: $0.pattern, categoryID: $0.category?.id, renameTo: $0.renameTo)
        }

        let choice = Categorizer.choose(merchant: merchant, type: type, rules: candidates)
        let category: TransactionCategory? = switch choice {
        case .category(let id): categories.first { $0.id == id }
        case .system(let key): categories.first { $0.systemKey == key }
        }

        let matched = Categorizer.matchingRule(for: MerchantKey.make(merchant), in: candidates)
        let rule = matched.flatMap { candidate in rules.first { $0.id == candidate.id } }
        return Resolution(category: category, renamedMerchant: rule?.renameTo, rule: rule)
    }

    public static func category(withID id: UUID, in context: ModelContext) throws -> TransactionCategory? {
        try context.fetch(FetchDescriptor<TransactionCategory>(predicate: #Predicate { $0.id == id })).first
    }

    /// Case-insensitive name match (used by Siri "Add expense … category Dining").
    public static func category(named name: String, in context: ModelContext) throws -> TransactionCategory? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        return try ensureDefaultCategories(in: context).first { $0.name.lowercased() == wanted }
    }

    /// Categorises transactions that have none (Phase 1 data, or after their category was deleted). Returns the count.
    @discardableResult
    public static func backfillUncategorized(in context: ModelContext) throws -> Int {
        let uncategorized = try context.fetch(FetchDescriptor<Transaction>()).filter { $0.category == nil }
        for transaction in uncategorized {
            transaction.category = try resolve(
                merchant: transaction.originalMerchant ?? transaction.merchant, type: transaction.type, in: context
            ).category
        }
        return uncategorized.count
    }
}
