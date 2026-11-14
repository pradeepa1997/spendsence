import Foundation

public enum MerchantCleaner {
    private static let edgePunctuation = CharacterSet(charactersIn: ".,;:-*/!?#").union(.whitespaces)

    /// Sri Lankan province + country suffixes found at the end of card merchant descriptors (`WPLK` = Western, LK).
    private static let provinceSuffixes: Set<String> = [
        "WPLK", "CPLK", "SPLK", "NPLK", "EPLK", "NWLK", "NCLK", "UPLK", "SGLK",
    ]

    /// Trim, collapse spaces, drop edge punctuation, Title Case. All-caps tokens of ≤ 3 letters stay as-is
    /// (`KFC`, `HNB`). Card descriptors are tidied: a trailing province code (`WPLK`) is dropped and a repeated
    /// word (`PILIYANDALA PILIYANDALA`) is collapsed. Returns nil for empty or purely numeric/punctuation results.
    public static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: edgePunctuation)
        guard trimmed.contains(where: { $0.isLetter }) else { return nil }

        var words = trimmed.split(separator: " ").map(String.init)
        if words.count > 1, let last = words.last, provinceSuffixes.contains(last.uppercased()) {
            words.removeLast()
        }
        words = words.reduce(into: [String]()) { result, word in
            if result.last?.lowercased() != word.lowercased() { result.append(word) }
        }
        return words.map { titleCase(Substring($0)) }.joined(separator: " ")
    }

    private static func titleCase(_ token: Substring) -> String {
        let letterCount = token.filter(\.isLetter).count
        if letterCount > 0, letterCount <= 3, token == token.uppercased() {
            return String(token)
        }
        return token.prefix(1).uppercased() + token.dropFirst().lowercased()
    }
}
