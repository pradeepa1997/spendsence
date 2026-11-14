import Foundation

/// Normalized merchant text for matching: uppercase letters/digits, single spaces.
/// `"Uber Eats, LK"` → `"UBER EATS LK"`, `"NETFLIX.COM"` → `"NETFLIX COM"`.
public enum MerchantKey {
    public static func make(_ merchant: String?) -> String? {
        guard let merchant else { return nil }
        let mapped = merchant.uppercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        let key = String(mapped).split(separator: " ").joined(separator: " ")
        return key.isEmpty ? nil : key
    }

    /// Whole-word containment: pattern `UBER` matches `UBER TRIP` but not `UBERX`; `SPAR` doesn't match `SPARK`.
    public static func matches(_ key: String, pattern: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        return (" " + key + " ").contains(" " + pattern + " ")
    }
}
