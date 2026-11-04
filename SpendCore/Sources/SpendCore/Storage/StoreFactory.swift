import Foundation
import SwiftData

public enum StoreFactory {
    public static var schema: Schema {
        Schema([RawMessage.self, Transaction.self, Account.self])
    }

    /// Creates the SwiftData container.
    ///
    /// - Parameter inMemory: `true` for tests. Each in-memory container is isolated.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = schema
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration(schema: schema, url: try storeURL())
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// `<App Group>/Store/SpendSense.store`, falling back to a temp directory when no App Group is available
    /// (e.g. `swift test` on macOS).
    ///
    /// The `Store/` directory is created with `completeUntilFirstUserAuthentication` protection **before** the
    /// container exists. Message automations fire while the phone is locked; with the default `.complete`
    /// protection those writes would fail. Files created inside the directory inherit its protection class.
    public static func storeURL() throws -> URL {
        let fileManager = FileManager.default
        let directory = baseDirectory().appendingPathComponent("Store", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        #endif
        return directory.appendingPathComponent("SpendSense.store")
    }

    private static func baseDirectory() -> URL {
        #if os(iOS)
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SpendCoreInfo.appGroupIdentifier
        ) {
            return group
        }
        #endif
        return FileManager.default.temporaryDirectory.appendingPathComponent("SpendSense", isDirectory: true)
    }
}
