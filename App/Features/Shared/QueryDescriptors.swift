import Foundation
import SwiftData
import SpendCore

/// Fetch descriptors used by `@Query`. Kept outside the views: referencing a view's own static from its
/// `@Query(...)` attribute can trigger "Circular reference resolving attached macro 'Query'".
enum QueryDescriptors {
    /// Low-confidence transactions the user hasn't approved or edited yet.
    static var awaitingReview: FetchDescriptor<SpendCore.Transaction> {
        let threshold = ParsingPipeline.autoAcceptThreshold - 1e-9
        return FetchDescriptor<SpendCore.Transaction>(
            predicate: #Predicate { $0.confidence < threshold && $0.isReviewed == false }
        )
    }

    /// The most recent message delivered by the Shortcuts automation (Simulate-tab messages excluded).
    static var latestAutomationMessage: FetchDescriptor<RawMessage> {
        let sms = TransactionSource.sms.rawValue
        var descriptor = FetchDescriptor<RawMessage>(
            predicate: #Predicate { $0.sourceRaw == sms },
            sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }
}
