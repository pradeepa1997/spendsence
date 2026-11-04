/// SpendCore: models, storage, SMS parsing and ingestion for SpendSense.
///
/// Everything in `Parsing/` is pure and SwiftData-free so it can be unit tested in isolation.
/// The only write path into the store is `IngestionService.ingest`.
public enum SpendCoreInfo {
    public static let appGroupIdentifier = "group.com.pradeepa.spendsense"
}
