import SwiftData
import SwiftUI
import SpendCore

@main
struct SpendSenseApp: App {
    var body: some Scene {
        WindowGroup {
            // One container per process: the same one IngestionService.shared (App Intent, Simulate tab) uses.
            switch SharedStore.containerResult {
            case .success(let container):
                RootTabView()
                    .modelContainer(container)
            case .failure(let error):
                ContentUnavailableView(
                    "Storage unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
            }
        }
    }
}
