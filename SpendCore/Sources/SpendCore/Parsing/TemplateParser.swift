import Foundation

/// Stage 3: bank-specific templates. The first template that captures a valid `amount` wins.
public struct TemplateParser: Sendable {
    public let library: TemplateLibrary
    public let classifier: MessageClassifier

    public init(library: TemplateLibrary = .bundled, classifier: MessageClassifier = .standard) {
        self.library = library
        self.classifier = classifier
    }

    public func parse(_ message: NormalizedMessage, sender: String?, receivedAt: Date) -> ParsedTransaction? {
        let text = message.text
        for compiled in library.ordered(for: sender) {
            guard let match = compiled.regex.firstMatch(in: text) else { continue }

            func group(_ name: String) -> String? {
                guard compiled.groupNames.contains(name) else { return nil }
                let value = CompiledRegex.substring(of: text, range: match.range(withName: name))
                return value?.isEmpty == true ? nil : value
            }

            guard let amountText = group("amount"), let amount = AmountParser.parse(amountText) else { continue }

            let merchant = MerchantCleaner.clean(group("merchant"))
            let last4 = group("last4").flatMap(Self.lastFourDigits)
            let balance = group("balance").flatMap(AmountParser.parseBalance)
            var occurredAt: Date?
            if let dateText = group("date"), let format = compiled.template.dateFormat {
                occurredAt = DateParsing.parse(dateText, format: format, receivedAt: receivedAt)
            }

            // Confidence in integer points to avoid floating-point drift at the 0.75 threshold.
            let points = merchant == nil ? 90 : 95
            return ParsedTransaction(
                amount: amount,
                currency: group("currency")?.uppercased() ?? "LKR",
                type: transactionType(for: compiled, text: text),
                merchant: merchant,
                last4: last4,
                balanceAfter: balance,
                occurredAt: occurredAt,
                bankName: compiled.template.bankName,
                confidence: Double(points) / 100,
                matchedTemplateID: compiled.template.id
            )
        }
        return nil
    }

    /// Decided by the template's own keywords; credit wording that means a refund/reversal becomes `.refund`.
    private func transactionType(for compiled: CompiledTemplate, text: String) -> TransactionType {
        let verbs = classifier.verbText(text)
        if compiled.creditKeywords.contains(verbs) {
            return classifier.isRefund(verbText: verbs) ? .refund : .credit
        }
        return .debit
    }

    static func lastFourDigits(_ raw: String) -> String? {
        let digits = raw.filter { $0 >= "0" && $0 <= "9" }
        return digits.count >= 4 ? String(digits.suffix(4)) : nil
    }
}
