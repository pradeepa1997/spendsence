import Foundation

public enum MerchantCleaner {
    private static let edgePunctuation = CharacterSet(charactersIn: ".,;:-*/!?#").union(.whitespaces)

    /// Trim, collapse spaces, drop edge punctuation, Title Case. All-caps tokens of ≤ 3 letters stay as-is
    /// (`KFC`, `HNB`). Returns nil for empty or purely numeric/punctuation results.
    public static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: edgePunctuation)
        guard trimmed.contains(where: { $0.isLetter }) else { return nil }
        return trimmed.split(separator: " ").map(titleCase).joined(separator: " ")
    }

    private static func titleCase(_ token: Substring) -> String {
        let letterCount = token.filter(\.isLetter).count
        if letterCount > 0, letterCount <= 3, token == token.uppercased() {
            return String(token)
        }
        return token.prefix(1).uppercased() + token.dropFirst().lowercased()
    }
}
