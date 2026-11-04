import Foundation

/// normalize → classify → template match → generic fallback → confidence decision.
/// Pure and SwiftData-free; dedup and saving happen in `IngestionService`.
public struct ParsingPipeline: Sendable {
    /// Bump whenever parsing output for an existing message would change.
    public static let version = 1
    /// Transactions at or above this confidence are auto-accepted; below it they are saved as needsReview.
    public static let autoAcceptThreshold = 0.75

    public enum Outcome: Sendable, Equatable {
        case parsed(ParsedTransaction)
        case ignored(String)
        case needsReview(ParsedTransaction?, String)
    }

    public let classifier: MessageClassifier
    public let templateParser: TemplateParser
    public let genericParser: GenericParser

    public init(library: TemplateLibrary = .bundled, classifier: MessageClassifier = .standard) {
        self.classifier = classifier
        self.templateParser = TemplateParser(library: library, classifier: classifier)
        self.genericParser = GenericParser(classifier: classifier)
    }

    public func run(body: String, sender: String?, receivedAt: Date) -> Outcome {
        let message = Normalizer.normalize(body)

        switch classifier.classify(message) {
        case .ignore(let reason):
            return .ignored(reason)
        case .informational:
            return .ignored("Informational")
        case .transaction:
            break
        }

        guard var parsed = templateParser.parse(message, sender: sender, receivedAt: receivedAt)
            ?? genericParser.parse(message)
        else {
            return .needsReview(nil, "no amount")
        }
        if parsed.occurredAt == nil {
            parsed.occurredAt = receivedAt
        }

        if parsed.confidence >= Self.autoAcceptThreshold - 1e-9 {
            return .parsed(parsed)
        }
        return .needsReview(parsed, "low confidence")
    }
}
