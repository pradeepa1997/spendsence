import Foundation
import SwiftData

/// The one on-disk `ModelContainer` for this process.
///
/// Created lazily on first access and shared by the SwiftUI app (`.modelContainer(...)`) and
/// `IngestionService.shared` (used by the App Intent and the Simulate tab). Never create another one.
public enum SharedStore {
    public static let containerResult: Result<ModelContainer, any Error> = Result {
        try StoreFactory.makeContainer()
    }
}
