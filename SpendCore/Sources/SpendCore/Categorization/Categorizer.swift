import Foundation

/// A merchant rule as a plain value, so categorisation stays pure and testable.
public struct RuleCandidate: Sendable, Equatable {
    public let id: UUID
    public let pattern: String
    public let categoryID: UUID?
    public let renameTo: String?

    public init(id: UUID = UUID(), pattern: String, categoryID: UUID? = nil, renameTo: String? = nil) {
        self.id = id
        self.pattern = pattern
        self.categoryID = categoryID
        self.renameTo = renameTo
    }
}

public enum CategoryChoice: Sendable, Equatable {
    /// A specific category (from a merchant rule).
    case category(UUID)
    /// A default category by `DefaultCategories` key.
    case system(String)
}

/// Picks a category: merchant rule → credit/transfer defaults → built-in keywords → Other.
public enum Categorizer {
    /// Checked in order, so more specific groups come first (UBER EATS → Dining before UBER → Transport,
    /// ATM CHARGES → Fees before ATM → Transfers). Keywords are `MerchantKey`s matched as whole words.
    public static let keywordGroups: [(key: String, keywords: [String])] = [
        (DefaultCategories.dining, [
            "UBER EATS", "PICKME FOOD", "PICKMEFOOD", "FOODPANDA", "KFC", "PIZZA HUT", "MCDONALDS", "MCDONALD",
            "BURGER KING", "DOMINOS", "SUBWAY", "STARBUCKS", "JAVA LOUNGE", "BARISTA", "CAFE", "COFFEE",
            "RESTAURANT", "BAKERY", "PILAWOOS", "FOOD COURT", "HOTEL",
        ]),
        (DefaultCategories.fees, [
            "CHARGE", "CHARGES", "FEE", "FEES", "COMMISSION", "LATE PAYMENT", "INTEREST", "STAMP DUTY",
        ]),
        (DefaultCategories.groceries, [
            "KEELLS", "CARGILLS", "FOOD CITY", "ARPICO", "SPAR", "GLOMARK", "LAUGFS SUPER", "SATHOSA",
            "SUPERMARKET", "SUPER MARKET",
        ]),
        (DefaultCategories.transport, [
            "PICKME", "UBER", "KANGAROO", "TAXI", "CEYPETCO", "IOC", "FUEL", "FILLING STATION", "PETROL",
            "PARKING", "EXPRESSWAY", "SLTB", "RAILWAY",
        ]),
        (DefaultCategories.bills, [
            "DIALOG", "SLT", "MOBITEL", "HUTCH", "AIRTEL", "CEB", "LECO", "WATER BOARD", "NWSDB",
            "ELECTRICITY", "RELOAD", "INSURANCE",
        ]),
        (DefaultCategories.health, [
            "PHARMACY", "PHARMA", "HOSPITAL", "HOSPITALS", "OSU SALA", "ASIRI", "NAWALOKA", "DURDANS",
            "HEALTHGUARD", "HEALTH GUARD", "MEDICAL", "CLINIC", "DENTAL", "CHANNELLING", "CHANNELING",
        ]),
        (DefaultCategories.shopping, [
            "DARAZ", "ODEL", "ABANS", "SINGER", "SOFTLOGIC", "AMAZON", "ALIEXPRESS", "TEMU", "SHEIN",
            "NOLIMIT", "NO LIMIT", "FASHION BUG", "COOL PLANET", "HOUSE OF FASHION",
        ]),
        (DefaultCategories.entertainment, [
            "NETFLIX", "SPOTIFY", "YOUTUBE", "APPLE COM BILL", "STEAM", "PLAYSTATION", "SCOPE CINEMAS",
            "CINEMA", "PVR", "DISNEY",
        ]),
        (DefaultCategories.travel, [
            "SRILANKAN", "AIRLINES", "AIRLINE", "EMIRATES", "QATAR AIRWAYS", "BOOKING COM", "AGODA", "AIRBNB",
            "EXPEDIA",
        ]),
        (DefaultCategories.education, [
            "SCHOOL", "UNIVERSITY", "COURSERA", "UDEMY", "TUITION", "INSTITUTE", "SARASAVI",
        ]),
        (DefaultCategories.transfers, [
            "ATM", "CEFT", "TRANSFER", "TFR", "LPAY", "LANKAPAY", "WITHDRAWAL", "JUSTPAY",
        ]),
    ]

    public static func choose(merchant: String?, type: TransactionType, rules: [RuleCandidate]) -> CategoryChoice {
        let key = MerchantKey.make(merchant)
        if let categoryID = matchingRule(for: key, in: rules.filter { $0.categoryID != nil })?.categoryID {
            return .category(categoryID)
        }
        switch type {
        case .credit: return .system(DefaultCategories.income)
        case .transfer: return .system(DefaultCategories.transfers)
        case .debit, .refund, .unknown: break
        }
        return .system(keywordCategory(for: key) ?? DefaultCategories.other)
    }

    /// Exact pattern first, otherwise the longest pattern contained (as whole words) in the merchant key.
    public static func matchingRule(for merchantKey: String?, in rules: [RuleCandidate]) -> RuleCandidate? {
        guard let merchantKey else { return nil }
        if let exact = rules.first(where: { $0.pattern == merchantKey }) { return exact }
        return rules
            .filter { MerchantKey.matches(merchantKey, pattern: $0.pattern) }
            .max { $0.pattern.count < $1.pattern.count }
    }

    public static func keywordCategory(for merchantKey: String?) -> String? {
        guard let merchantKey else { return nil }
        for group in keywordGroups where group.keywords.contains(where: { MerchantKey.matches(merchantKey, pattern: $0) }) {
            return group.key
        }
        return nil
    }
}
