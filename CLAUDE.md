# CLAUDE.md — SpendSense

iOS expense tracker that ingests bank SMS via a Shortcuts automation → App Intent. Fully on-device.
Requirements: `PHASE1_SPEC.md` (ingestion), `PHASE2_SPEC.md` (categories, editing, review, dashboard).

## Commands
```bash
xcodegen generate                       # after any project.yml change
cd SpendCore && swift test              # parser + store tests (macOS)
xcodebuild -scheme SpendSense -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Hard rules
- **Never hand-edit `.xcodeproj`.** Change `project.yml` and regenerate. The project file is gitignored.
- **No third-party dependencies.**
- Swift 6, strict concurrency. Zero warnings.
- **Write paths:** SMS (App Intent, Simulate) → `IngestionService.ingest` only. User edits, manual/cash entries,
  categories and merchant rules → `TransactionEditor` (on the view's `modelContext`; Siri reaches it via
  `IngestionService.addExpense`). Views never mutate models directly. Every SMS-sourced Transaction has a `RawMessage`.
- Categorisation lives in `Categorization/` (`Categorizer` is pure; `CategoryService` touches SwiftData). New keywords
  go in `Categorizer.keywordGroups` with a test in `Phase2Tests`.
- `TransactionCategory` (not `Category`, which clashes with the Objective-C runtime typedef).
- The RawMessage is persisted **before** parsing; `ingest` never throws.
- Everything under `SpendCore/Sources/SpendCore/Parsing` is pure, `Sendable`, and has no SwiftData import.
- Only one `ModelContainer` per process: `SharedStore.containerResult`. The app injects it; `IngestionService.shared` uses it.
- The store directory keeps `FileProtectionType.completeUntilFirstUserAuthentication` (automations run while locked).
- Parser misses become fixtures in `SpendCore/Tests/SpendCoreTests/Fixtures/sms_samples.json` first, then fixes.
- Bump `ParsingPipeline.version` whenever parsing output changes for existing messages.

## Layout
- `App/`: SwiftUI app, App Intents (`App/Intents`), feature views (`App/Features`: Dashboard, Transactions, Review, More,
  Messages, Simulate, Shared). Tabs: Dashboard · Transactions · Review · More.
- `SpendCore/Sources/SpendCore/`: `Models`, `Storage`, `Parsing`, `Ingestion`, `Categorization`, `Editing`, `Summary`,
  `Support`, `Resources/templates.json`.
- `SpendCore/Tests/SpendCoreTests/`: Swift Testing suites + JSON fixture corpus.

## Spec deviations (agreed)
See README → "Design decisions & deviations from the spec".
