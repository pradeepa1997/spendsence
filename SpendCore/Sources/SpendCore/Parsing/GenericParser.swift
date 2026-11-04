import Foundation

/// Stage 4: bank-agnostic fallback heuristics.
public struct GenericParser: Sendable {
    public let classifier: MessageClassifier

    public init(classifier: MessageClassifier = .standard) {
        self.classifier = classifier
    }

    private static let currencies = Normalizer.currencyCodes.joined(separator: "|")

    /// Currency code + amount. The amount must start with a digit.
    static let amountRegex = CompiledRegex(#"(?<![A-Za-z])("# + currencies + #")\s?(\d[\d,]*(?:\.\d{1,2})?)"#)

    /// Amounts directly preceded by these words are balances/limits/dues, not the transaction amount.
    static let nonTransactionAmountLead = CompiledRegex(#"\b(?:bal|balance|limit|due)\b[^\d]*$"#)

    /// Merchant starts after " at ", " to " or " @ ".
    static let merchantLead = CompiledRegex(#"(?:^|\s)(?:at|to|@)\s+"#)

    /// …and runs up to " on ", " ref", " via ", similar connector words, or `.`/`,`/`;` followed by a space.
    static let merchantBody = CompiledRegex(
        #"^(.+?)(?=\s+(?:ref|(?:on|via|for|using|with|from|is|has|was|dated|avl|bal|thank|txn|card|credited|debited|reversed|refunded)\b)|[.,;](?:\s|$)|\s*$)"#
    )

    /// First words that mean the "merchant" is really the user's own account.
    static let merchantStopWords: Set<String> = ["your", "you", "a/c", "ac", "acct", "account", "card", "the"]

    static let last4Regex = CompiledRegex(#"(?:card|a/c|acct|account)[^\d]{0,15}\d*?(\d{4})(?!\d)"#)

    static let balanceRegex = CompiledRegex(
        #"(?:\bavl\.?\s*bal(?:ance)?|\bbal(?:ance)?)[^\d]{0,10}(?:LKR\s?)?(\d[\d,]*(?:\.\d{1,2})?)"#
    )

    public func parse(_ message: NormalizedMessage) -> ParsedTransaction? {
        let text = message.text
        guard let (currency, amount) = Self.findAmount(in: text) else { return nil }

        let merchant = Self.findMerchant(in: text)
        let last4 = Self.last4Regex.firstCapture(in: text)
        let balance = Self.balanceRegex.firstCapture(in: text).flatMap(AmountParser.parseBalance)
        let verbs = classifier.verbText(text)

        // Integer points avoid floating-point drift at the 0.75 threshold.
        var points = 60
        if merchant != nil { points += 10 }
        if last4 != nil { points += 5 }
        if !classifier.hasTransactionVerb(verbText: verbs) { points -= 15 }

        return ParsedTransaction(
            amount: amount,
            currency: currency,
            type: classifier.transactionType(verbText: verbs),
            merchant: merchant,
            last4: last4,
            balanceAfter: balance,
            occurredAt: nil,
            bankName: nil,
            confidence: Double(points) / 100,
            matchedTemplateID: nil
        )
    }

    static func findAmount(in text: String) -> (currency: String, amount: Decimal)? {
        let ns = text as NSString
        for match in amountRegex.matches(in: text) {
            let start = match.range.location
            let lookbackStart = max(0, start - 20)
            let before = ns.substring(with: NSRange(location: lookbackStart, length: start - lookbackStart))
            if nonTransactionAmountLead.contains(before) { continue }
            guard let currency = CompiledRegex.substring(of: text, range: match.range(at: 1)),
                  let amountText = CompiledRegex.substring(of: text, range: match.range(at: 2)),
                  let amount = AmountParser.parse(amountText)
            else { continue }
            return (currency.uppercased(), amount)
        }
        return nil
    }

    static func findMerchant(in text: String) -> String? {
        let ns = text as NSString
        for lead in merchantLead.matches(in: text) {
            let rest = ns.substring(from: lead.range.location + lead.range.length)
            guard let candidate = merchantBody.firstCapture(in: rest) else { continue }
            let firstWord = candidate.split(separator: " ").first.map { $0.lowercased() } ?? ""
            if merchantStopWords.contains(firstWord) { continue }
            if amountRegex.contains(candidate) { continue }
            if let cleaned = MerchantCleaner.clean(candidate) { return cleaned }
        }
        return nil
    }
}
