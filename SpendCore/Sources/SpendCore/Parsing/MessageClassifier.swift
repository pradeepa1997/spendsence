import Foundation

public enum MessageClassification: Sendable, Equatable {
    case transaction
    case informational
    case ignore(String)
}

/// Rewrites a phrase before verb detection, e.g. "credit card" → "card" so that a card *purchase*
/// is not mistaken for a *credit*.
public struct PhraseRewrite: Sendable, Equatable {
    public var pattern: String
    public var replacement: String

    public init(pattern: String, replacement: String) {
        self.pattern = pattern
        self.replacement = replacement
    }
}

/// Every keyword list used for classification, in one place so it is easy to extend.
public struct ClassifierKeywords: Sendable {
    /// OTP / security messages. Ignored unless a `completedVerbs` word shows money actually moved
    /// (some banks append "never share your OTP" to real debit alerts).
    public var ignoreAlways: [String]
    /// Promotions. Ignored only when no debit/credit verb is present.
    public var ignoreUnlessVerb: [String]
    /// Reminders and statements. Informational only when no debit/credit verb is present.
    public var informational: [String]
    public var debitVerbs: [String]
    public var creditVerbs: [String]
    /// Subset of credit wording that means money came back (→ `.refund`).
    public var refundWords: [String]
    /// Past-tense verbs proving a completed money movement; they override `ignoreAlways`.
    public var completedVerbs: [String]
    /// Applied before verb detection.
    public var verbNeutralizers: [PhraseRewrite]

    public init(
        ignoreAlways: [String],
        ignoreUnlessVerb: [String],
        informational: [String],
        debitVerbs: [String],
        creditVerbs: [String],
        refundWords: [String],
        completedVerbs: [String],
        verbNeutralizers: [PhraseRewrite]
    ) {
        self.ignoreAlways = ignoreAlways
        self.ignoreUnlessVerb = ignoreUnlessVerb
        self.informational = informational
        self.debitVerbs = debitVerbs
        self.creditVerbs = creditVerbs
        self.refundWords = refundWords
        self.completedVerbs = completedVerbs
        self.verbNeutralizers = verbNeutralizers
    }

    public static let standard = ClassifierKeywords(
        ignoreAlways: ["otp", "one time password", "one-time password", "verification code", "do not share"],
        ignoreUnlessVerb: ["promo", "offer", "% off", "win ", "reward points"],
        informational: ["due date", "minimum payment", "min. due", "statement", "payment due", "total due"],
        debitVerbs: [
            "debited", "debit", "purchase", "purchased", "spent", "withdrawn", "withdrawal",
            "paid", "payment of", "txn", "transaction", "pos",
        ],
        creditVerbs: ["credited", "credit", "received", "deposited", "refund", "refunded", "reversed", "reversal"],
        refundWords: ["refund", "refunded", "reversed", "reversal"],
        completedVerbs: ["debited", "credited", "spent", "withdrawn", "purchased", "deposited", "refunded", "reversed"],
        verbNeutralizers: [
            PhraseRewrite(pattern: #"\b(?:credit|debit)\s+cards?\b"#, replacement: "card"),
            PhraseRewrite(pattern: #"\bcredit\s+(?:limit|line)\b"#, replacement: "limit"),
            PhraseRewrite(pattern: #"\bmin(?:imum|\.)?\s+payment\b"#, replacement: "minimum"),
            PhraseRewrite(pattern: #"\bpayment\s+due\b"#, replacement: "due"),
        ]
    )
}

/// Stage 2: decides whether a message is a transaction, informational, or noise.
public struct MessageClassifier: Sendable {
    public static let standard = MessageClassifier()

    /// A currency code followed by a number.
    static let amountPattern = CompiledRegex(
        #"(?<![A-Za-z])(?:"# + Normalizer.currencyCodes.joined(separator: "|") + #")\s?\d"#
    )

    private struct Rewrite: Sendable {
        let regex: CompiledRegex
        let replacement: String
    }

    public let keywords: ClassifierKeywords
    private let ignoreAlways: CompiledRegex
    private let ignoreUnlessVerb: CompiledRegex
    private let informational: CompiledRegex
    private let debitVerbs: CompiledRegex
    private let creditVerbs: CompiledRegex
    private let refundWords: CompiledRegex
    private let completedVerbs: CompiledRegex
    private let rewrites: [Rewrite]

    public init(keywords: ClassifierKeywords = .standard) {
        self.keywords = keywords
        ignoreAlways = .keywords(keywords.ignoreAlways, wholeWord: false)
        ignoreUnlessVerb = .keywords(keywords.ignoreUnlessVerb, wholeWord: false)
        informational = .keywords(keywords.informational, wholeWord: false)
        debitVerbs = .keywords(keywords.debitVerbs, wholeWord: true)
        creditVerbs = .keywords(keywords.creditVerbs, wholeWord: true)
        refundWords = .keywords(keywords.refundWords, wholeWord: true)
        completedVerbs = .keywords(keywords.completedVerbs, wholeWord: true)
        rewrites = keywords.verbNeutralizers.compactMap { rewrite in
            guard let regex = try? CompiledRegex(validating: rewrite.pattern) else { return nil }
            return Rewrite(regex: regex, replacement: rewrite.replacement)
        }
    }

    public func classify(_ message: NormalizedMessage) -> MessageClassification {
        let lower = message.text.lowercased()
        let verbs = verbText(message.text)
        let hasVerb = hasTransactionVerb(verbText: verbs)

        if ignoreAlways.contains(lower), !completedVerbs.contains(verbs) {
            return .ignore("OTP")
        }
        if !hasVerb, ignoreUnlessVerb.contains(lower) {
            return .ignore("Promotional")
        }
        if !hasVerb, informational.contains(lower) {
            return .informational
        }
        // An amount without a verb is still passed on: the parsers penalise it so it lands in needsReview.
        if hasVerb || Self.amountPattern.contains(message.text) {
            return .transaction
        }
        return .ignore("Not a transaction")
    }

    /// Lowercased text with neutralizing rewrites applied ("credit card" → "card", …). Use for verb detection.
    public func verbText(_ text: String) -> String {
        rewrites.reduce(text.lowercased()) { partial, rewrite in
            rewrite.regex.replacingMatches(in: partial, with: rewrite.replacement)
        }
    }

    public func hasTransactionVerb(verbText: String) -> Bool {
        debitVerbs.contains(verbText) || creditVerbs.contains(verbText)
    }

    public func isRefund(verbText: String) -> Bool {
        refundWords.contains(verbText)
    }

    /// Refund wording → `.refund`. Otherwise credit vs debit by whichever verb appears first; no verb → `.debit`.
    public func transactionType(verbText: String) -> TransactionType {
        if isRefund(verbText: verbText) { return .refund }
        let credit = creditVerbs.firstMatch(in: verbText)?.range.location
        let debit = debitVerbs.firstMatch(in: verbText)?.range.location
        switch (credit, debit) {
        case (nil, _): return .debit
        case (.some, nil): return .credit
        case let (credit?, debit?): return credit < debit ? .credit : .debit
        }
    }
}
