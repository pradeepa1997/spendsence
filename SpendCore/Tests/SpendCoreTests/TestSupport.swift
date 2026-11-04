import Foundation
@testable import SpendCore

enum TestSupport {
    /// 2026-09-12T08:00:00Z
    static let t0 = Date(timeIntervalSince1970: 1_789_200_000)

    static func makeService(
        stepHook: (@Sendable (IngestionStep) throws -> Void)? = nil
    ) throws -> (IngestionService, TransactionStore) {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let service = IngestionService(containerResult: .success(container), stepHook: stepHook)
        guard let store = service.store else { throw TestError.noStore }
        return (service, store)
    }

    enum TestError: Error { case noStore }

    struct InjectedFailure: LocalizedError {
        var errorDescription: String? { "Injected failure" }
    }
}
