import Foundation

public struct ParsingPipeline: Sendable {
    /// Bump whenever parsing output for an existing message would change.
    public static let version = 1
    /// Transactions at or above this confidence are auto-accepted; below it they are saved as needsReview.
    public static let autoAcceptThreshold = 0.75
}
