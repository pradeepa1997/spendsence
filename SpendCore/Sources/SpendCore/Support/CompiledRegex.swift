import Foundation

/// Thin wrapper around `NSRegularExpression` with String-friendly helpers.
///
/// `NSRegularExpression` is immutable and documented as safe to use concurrently from multiple threads,
/// so `@unchecked Sendable` is sound here.
public struct CompiledRegex: @unchecked Sendable {
    public let regex: NSRegularExpression

    /// For patterns written in source code. An invalid literal is a programmer error caught by the tests.
    init(_ pattern: String, caseInsensitive: Bool = true) {
        do {
            regex = try NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        } catch {
            preconditionFailure("Invalid built-in regex \(pattern): \(error)")
        }
    }

    /// For patterns that come from data (templates). Throws instead of crashing.
    init(validating pattern: String, caseInsensitive: Bool = true) throws {
        regex = try NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    /// A regex that never matches.
    static let never = CompiledRegex("(?!)")

    /// Builds an alternation of literal keywords.
    /// A `\b` is added on each side of a keyword whose edge character is a word character
    /// (only on the leading side unless `wholeWord` is true), so `pos` never matches inside `deposit`.
    static func keywords(_ words: [String], wholeWord: Bool) -> CompiledRegex {
        let parts = words.filter { !$0.isEmpty }.map { word -> String in
            let escaped = NSRegularExpression.escapedPattern(for: word)
            let lead = isWordCharacter(word.first) ? #"\b"# : ""
            let trail = wholeWord && isWordCharacter(word.last) ? #"\b"# : ""
            return lead + escaped + trail
        }
        guard !parts.isEmpty else { return never }
        return CompiledRegex("(?:" + parts.joined(separator: "|") + ")")
    }

    func firstMatch(in string: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: string, range: Self.fullRange(of: string))
    }

    func matches(in string: String) -> [NSTextCheckingResult] {
        regex.matches(in: string, range: Self.fullRange(of: string))
    }

    func contains(_ string: String) -> Bool {
        firstMatch(in: string) != nil
    }

    func replacingMatches(in string: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: string, range: Self.fullRange(of: string), withTemplate: template)
    }

    /// The text of capture group `group` in the first match, if any.
    func firstCapture(_ group: Int = 1, in string: String) -> String? {
        guard let match = firstMatch(in: string) else { return nil }
        return Self.substring(of: string, range: match.range(at: group))
    }

    static func fullRange(of string: String) -> NSRange {
        NSRange(string.startIndex..., in: string)
    }

    static func substring(of string: String, range: NSRange) -> String? {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else { return nil }
        return String(string[swiftRange])
    }

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "_"
    }
}
