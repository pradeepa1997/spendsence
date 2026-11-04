# SpendSense — Phase 1 Spec

> Before handing over: replace the bundle ID and App Group placeholders, and add 10–20 real anonymized bank SMS to the fixtures. The seed templates are generic placeholder shapes, not exact bank formats.


---

### 1. Scope

### In scope (Phase 1)
1. Xcode project generated with XcodeGen, plus a local Swift package `SpendCore`.
2. SwiftData models and a shared store in an App Group container.
3. Rule-based SMS parsing pipeline: normalize → classify → template match → generic fallback → dedup → save.
4. `LogTransactionFromSMSIntent` (App Intent), callable from a Shortcuts automation with no UI.
5. A minimal SwiftUI app with three tabs:
   - **Transactions**: list plus a simple detail view.
   - **Messages**: raw SMS log with parse status, used for debugging.
   - **Simulate**: paste an SMS and run it through the exact same ingestion path.
6. Unit tests for the parser, run against a JSON fixture corpus.

### Out of scope (later phases, do NOT build now)
- Categories UI and budgets. A single `categoryName: String?` field is enough in Phase 1.
- On-device LLM (Foundation Models), the template builder, and the review queue UI.
- Onboarding flow, notifications, widgets, charts, export, iCloud sync, Face ID lock.

---

### 2. Tech constraints

| Item | Value |
|---|---|
| Xcode | 26.x |
| Swift | 6, strict concurrency ON |
| iOS deployment target | 17.0 |
| SpendCore platforms | `.iOS(.v17), .macOS(.v14)` (macOS is only there so `swift test` runs on the Mac) |
| Persistence | SwiftData |
| Testing | Swift Testing (`import Testing`) |
| Project generation | XcodeGen (`project.yml`) — **never hand-edit `.xcodeproj`** |
| Third-party dependencies | **None** |
| Bundle ID | `com.pradeepa.spendsense` (placeholder — confirm) |
| App Group | `group.com.pradeepa.spendsense` |

---

### 3. Repository layout

```
SpendSense/
├── PHASE1_SPEC.md
├── CLAUDE.md
├── project.yml
├── App/
│   ├── SpendSenseApp.swift
│   ├── RootTabView.swift
│   ├── SpendSense.entitlements        # App Group
│   ├── Info.plist
│   ├── Intents/
│   │   ├── LogTransactionFromSMSIntent.swift
│   │   └── SpendSenseShortcuts.swift   # AppShortcutsProvider
│   └── Features/
│       ├── Transactions/TransactionListView.swift
│       ├── Transactions/TransactionDetailView.swift
│       ├── Messages/RawMessageListView.swift
│       └── Simulate/SimulateSMSView.swift
└── SpendCore/
    ├── Package.swift
    ├── Sources/SpendCore/
    │   ├── Models/
    │   │   ├── RawMessage.swift
    │   │   ├── Transaction.swift
    │   │   ├── Account.swift
    │   │   └── Enums.swift
    │   ├── Storage/
    │   │   ├── StoreFactory.swift
    │   │   └── TransactionStore.swift      # @ModelActor
    │   ├── Parsing/
    │   │   ├── ParsedTransaction.swift
    │   │   ├── Normalizer.swift
    │   │   ├── MessageClassifier.swift
    │   │   ├── ParserTemplate.swift
    │   │   ├── TemplateLibrary.swift
    │   │   ├── TemplateParser.swift
    │   │   ├── GenericParser.swift
    │   │   ├── AmountParser.swift
    │   │   └── ParsingPipeline.swift
    │   ├── Ingestion/
    │   │   └── IngestionService.swift       # single entry point used by intent + Simulate tab
    │   └── Resources/
    │       └── templates.json
    └── Tests/SpendCoreTests/
        ├── Fixtures/sms_samples.json
        ├── NormalizerTests.swift
        ├── AmountParserTests.swift
        ├── ClassifierTests.swift
        ├── PipelineFixtureTests.swift
        ├── DedupTests.swift
        └── IngestionServiceTests.swift
```

---

### 4. Data model (SpendCore/Models)

All models are `@Model final class`, and all are `public`.

### Enums.swift
```swift
public enum TransactionType: String, Codable, Sendable { case debit, credit, refund, transfer, unknown }
public enum MessageStatus: String, Codable, Sendable { case pending, parsed, ignored, needsReview, duplicate, failed }
public enum TransactionSource: String, Codable, Sendable { case sms, manual, simulated }
```

### RawMessage
| Field | Type | Notes |
|---|---|---|
| id | UUID | `@Attribute(.unique)` |
| body | String | exactly as received |
| sender | String? | |
| receivedAt | Date | |
| statusRaw | String | backing store for `status: MessageStatus` (computed) |
| parserVersion | Int | constant `ParsingPipeline.version`, starting at 1 |
| failureReason | String? | |
| bodyHash | String | SHA-256 of trimmed body (CryptoKit), used for exact-duplicate detection |
| transaction | Transaction? | inverse relationship |

### Transaction
| Field | Type | Notes |
|---|---|---|
| id | UUID | unique |
| amount | Decimal | always positive; direction comes from `type` |
| currency | String | ISO code, default `"LKR"` |
| typeRaw | String | backing store for `TransactionType` |
| merchant | String? | cleaned, Title Case |
| occurredAt | Date | parsed date from the SMS if present, else `receivedAt` |
| balanceAfter | Decimal? | |
| confidence | Double | 0…1 |
| sourceRaw | String | backing store for `TransactionSource` |
| categoryName | String? | Phase 1 placeholder |
| isUserEdited | Bool | default false |
| createdAt | Date | |
| account | Account? | relationship |
| rawMessage | RawMessage? | relationship, delete rule `.nullify` |

### Account
| Field | Type | Notes |
|---|---|---|
| id | UUID | unique |
| bankName | String | e.g. from template `bankName` |
| last4 | String? | |
| displayName | String | default `"\(bankName) ••\(last4)"` |
| transactions | [Transaction] | inverse |

**Matching rule:** match an existing Account on (`bankName`, `last4`). If none matches, create one. If `last4` is nil, use a single “\(bankName) (unknown)” account.

---

### 5. Storage

### StoreFactory
- `public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer`
- On-disk location: `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` + `Store/SpendSense.store`.
- **Before creating the container**, create the `Store/` directory and set
  `FileProtectionType.completeUntilFirstUserAuthentication` on it with
  `FileManager.setAttributes`. Message automations can fire while the device is locked,
  and the default `.complete` protection would make those writes fail. This is a hard requirement.
- If the App Group container is nil (e.g. when running `swift test` on macOS), fall back to a temporary directory.
- `inMemory: true` is used by the tests.

### TransactionStore (`@ModelActor`)
- `func insertRawMessage(body:sender:receivedAt:) throws -> PersistentIdentifier`
- `func saveTransaction(_ parsed: ParsedTransaction, for rawID: PersistentIdentifier, source: TransactionSource) throws`
- `func updateStatus(_ rawID: PersistentIdentifier, status: MessageStatus, reason: String?) throws`
- `func findDuplicate(of parsed: ParsedTransaction, bodyHash: String, receivedAt: Date) throws -> Bool`
- `func upsertAccount(bankName:last4:) throws -> Account`

---

### 6. Parsing pipeline (SpendCore/Parsing)

All parsing types are **pure, `Sendable`, and have no SwiftData dependency**, so they can be unit-tested in isolation.

### ParsedTransaction (struct)
`amount: Decimal, currency: String, type: TransactionType, merchant: String?, last4: String?, balanceAfter: Decimal?, occurredAt: Date?, bankName: String?, confidence: Double, matchedTemplateID: String?`

### Stage 1 — Normalizer
Input: raw body. Output: `NormalizedMessage { original, text, upper }`.
- Collapse all whitespace, including newlines, to single spaces, then trim.
- Unify currency tokens (case-insensitive, word-bounded): `Rs.`, `Rs`, `LKR.`, `LKR`, `SLRs` → `LKR`. Keep `USD`, `EUR`, `GBP`, `INR`, `AUD`, `SGD` as-is.
- Ensure a single space between the currency code and the amount (`LKR1,250.00` → `LKR 1,250.00`).
- Do NOT strip commas globally. Commas inside amounts are handled by `AmountParser`.

### Stage 2 — MessageClassifier
Returns `.transaction`, `.informational`, or `.ignore(reason)`.
- **Ignore** if the text contains any of these (case-insensitive): `OTP`, `one time password`, `one-time password`, `verification code`, `do not share`, `promo`, `offer`, `% off`, `win `, `reward points` (only when no debit or credit verb is present).
- **Informational** (not an expense) if it contains `due date`, `minimum payment`, `min. due`, `statement`, `payment due`, or `total due`, and no verb from the debit or credit list below.
- **Transaction** requires an amount pattern (a currency code followed by a number) plus at least one verb:
  - Debit verbs: `debited`, `debit`, `purchase`, `purchased`, `spent`, `withdrawn`, `withdrawal`, `paid`, `payment of`, `txn`, `transaction`, `pos`
  - Credit verbs: `credited`, `credit`, `received`, `deposited`, `refund`, `reversed`, `reversal`
- The keyword lists live in one `ClassifierKeywords` struct so they are easy to extend.

### Stage 3 — TemplateParser
- `ParserTemplate` is `Codable`: `id, bankName, senderHints: [String], pattern: String, debitKeywords: [String], creditKeywords: [String], dateFormat: String?`
- Patterns use **named capture groups**: `amount` (required), `currency`, `merchant`, `last4`, `balance`, `date`.
- `TemplateLibrary` loads `Resources/templates.json` with `Bundle.module` and compiles each pattern once into `NSRegularExpression` (case-insensitive). An invalid pattern is logged and skipped. It must never crash.
- Order of attempts: templates whose `senderHints` contains the sender (case-insensitive substring) first, then all remaining templates.
- The first template that captures a valid `amount` wins:
  - Type is decided by that template's keywords.
  - `confidence = 0.9`; add `0.05` if `merchant` was captured, capped at 0.95.

### Stage 4 — GenericParser (fallback)
- Amount: first `(?:LKR|USD|EUR|GBP|INR|AUD|SGD)\s?([\d,]+(?:\.\d{1,2})?)`.
- Merchant: text after ` at ` / ` to ` / ` @ ` up to the next ` on `, ` ref`, `.`, `,`, or ` via `.
- last4: `(?:card|a/c|acct|account)[^\d]{0,15}(?:x+|\*+|ending\s*(?:in\s*)?)?(\d{4})`.
- Balance: `(?:bal(?:ance)?|avl\.?\s*bal)[^\d]{0,10}(?:LKR\s?)?([\d,]+(?:\.\d{1,2})?)`.
- Type: a credit verb present → `.credit` (a refund or reversal verb → `.refund`); otherwise `.debit`.
- `confidence = 0.6`; add `0.1` if merchant was found and another `0.05` if last4 was found.

### AmountParser
- Strip `,` and spaces, then `Decimal(string:locale: Locale(identifier: "en_US_POSIX"))`.
- Reject nil, zero, negative, or greater than 100,000,000.

### Merchant cleaning
Trim, collapse spaces, drop trailing punctuation, and convert to Title Case. Keep all-caps tokens of 3 letters or fewer as-is (e.g. `KFC`). Return nil if the result is empty or purely numeric.

### Date parsing
Only used when a template supplies a `date` group together with a `dateFormat`. If parsing fails, fall back to `receivedAt`, never to nil.

### ParsingPipeline
```swift
public struct ParsingPipeline: Sendable {
    public static let version = 1
    public enum Outcome: Sendable { case parsed(ParsedTransaction), ignored(String), needsReview(ParsedTransaction?, String) }
    public func run(body: String, sender: String?, receivedAt: Date) -> Outcome
}
```
Decision rules:
- If the classifier returns `.ignore` or `.informational`, the outcome is `.ignored(reason)`.
- Try TemplateParser, then GenericParser. If neither yields an amount, the outcome is `.needsReview(nil, "no amount")`.
- If `confidence >= 0.75`, the outcome is `.parsed`; otherwise it is `.needsReview(parsed, "low confidence")`.

A `needsReview` result that has a ParsedTransaction is **still saved as a Transaction** (with its low confidence) so nothing is lost. RawMessage status is set to `needsReview`.

---

### 7. Ingestion service (the single entry point)

`public actor IngestionService` wraps `TransactionStore` plus `ParsingPipeline`.

```swift
public func ingest(body: String, sender: String?, receivedAt: Date = .now,
                   source: TransactionSource = .sms) async -> IngestionResult
```
Steps, in this exact order:
1. **Persist the RawMessage first** (status `pending`). The raw text must never be lost, even if a later step throws.
2. Run the pipeline.
3. For `.ignored`: set status to `ignored` with the reason, and return.
4. Dedup check. A message is a duplicate if:
   - the same `bodyHash` already exists, OR
   - there is an existing transaction with the same amount, the same account (bankName + last4), and `occurredAt` within ±3 minutes.

   If it is a duplicate, set status to `duplicate` and return.
5. Upsert the Account, save the Transaction linked to the RawMessage, and set status to `parsed` or `needsReview`.
6. Any thrown error sets status to `failed` with `failureReason`. The function never rethrows to the caller.

`IngestionResult` carries: `status`, a human-readable `summary` such as `"Logged LKR 2,450.00 – Keells Super"` or `"Ignored: OTP"`, and an optional transaction ID.

**Both the App Intent and the Simulate tab must call `IngestionService.ingest`.** There must be no second ingestion code path.

---

### 8. App Intents (App target)

### LogTransactionFromSMSIntent
- `title`: "Log Transaction from SMS"
- `description`: "Parses a bank SMS and saves it as a transaction."
- `static let openAppWhenRun = false`
- Parameters: `@Parameter(title: "Message") var message: String` and `@Parameter(title: "Sender") var sender: String?`
- `perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog`:
  - calls `IngestionService.shared.ingest(body: message, sender: sender)`
  - returns `.result(value: summary, dialog: "\(summary)")`
- The intent must complete quickly (well under 10 s) and must not touch any UI.

### SpendSenseShortcuts: AppShortcutsProvider
- Registers the intent with the phrase `"Log SMS in \(.applicationName)"`, a short title, and the `systemImageName` `"message.badge"`.

### Shared container
- `SpendSenseApp` creates **one** `ModelContainer` via `StoreFactory.makeContainer()` and injects it with `.modelContainer(...)`.
- `IngestionService.shared` uses that same container, as a lazily created singleton inside SpendCore. The intent and the UI must never create separate containers.

---

### 9. Minimal UI (App target)

**Transactions tab**
- A `@Query` list sorted by `occurredAt` descending, grouped by day.
- Each row shows merchant (or "Unknown"), account display name, amount, and time.
- Amounts are red for debit and green for credit or refund.
- Rows with `confidence < 0.75` get an orange "Review" badge.
- Tapping a row opens `TransactionDetailView`: all fields read-only, plus the original SMS text. Phase 1 has no editing.
- Empty state: "No transactions yet. Use the Simulate tab or set up the Shortcuts automation."

**Messages tab**
- A `@Query` list of RawMessage, newest first.
- Each row shows a status pill (color per status), the first 2 lines of the body, the sender, and the time. Tapping a row shows the full body plus `failureReason`.

**Simulate tab**
- A multiline `TextEditor` for the SMS body, an optional sender `TextField`, and a "Ingest" button.
- Shows the `IngestionResult.summary` after ingesting.
- A "Load sample" menu that inserts any fixture from a small built-in sample list.
- A "Delete all data" button in a toolbar menu (dev convenience), behind a confirmation dialog.

Keep the styling to default SwiftUI. No design work in Phase 1.

---

### 10. Seed templates (`templates.json`)

Create **3 illustrative templates** covering common Sri Lankan bank SMS shapes. These formats are placeholders written from generic patterns, and Pradeepa will replace or extend them with real anonymized samples. Each template must be matched by at least one fixture.

| Template | Example message shape |
|---|---|
| `generic_card_purchase` | `LKR 2,450.00 debited from card ending 1234 at KEELLS SUPER on 12/09/26. Avl Bal LKR 45,210.50` |
| `generic_account_credit` | `Your A/C xxxx5678 has been credited with LKR 150,000.00 on 25-09-2026. Bal: LKR 210,000.00` |
| `generic_pos_txn` | `Txn of LKR 850.00 at PICKME FOOD using card **9012 approved. Ref 88213` |

---

### 11. Test fixtures (`sms_samples.json`)

Schema:
```json
[
  {
    "id": "card_purchase_01",
    "sender": "BANKA",
    "body": "…",
    "expect": {
      "outcome": "parsed | ignored | needsReview",
      "amount": "2450.00",
      "currency": "LKR",
      "type": "debit",
      "merchant": "Keells Super",
      "last4": "1234",
      "balanceAfter": "45210.50"
    }
  }
]
```
Only assert the `expect` keys that are present in a fixture. Amounts are strings, so they compare as Decimal.

The initial corpus needs at least **20 synthetic samples**, including:
- **Template coverage:** at least 2 samples per template.
- **Formatting variants:** `Rs.` vs `LKR`, no space between currency and amount, amounts with no decimals, amounts of 1,000,000 or more, and line breaks inside the message.
- **Credits and refunds:** at least 2 of each (credit, refund or reversal).
- **Generic fallback:** at least 3 messages that only the generic parser can handle.
- **Ignored and informational:** at least 3 OTP messages, 2 promotional messages, and 2 "payment due" or statement reminders.
- **Low confidence:** 1 ambiguous message with an amount but no verb, and 1 message that yields `needsReview`.

`PipelineFixtureTests` must iterate every fixture with a parameterized `@Test(arguments:)` and print the fixture `id` on failure.

**TODO for Pradeepa:** add real anonymized bank SMS (replace names, digits, and reference numbers) to this file, then add or adjust templates until every test is green.

---

### 12. Required tests

- **NormalizerTests:** currency unification, whitespace collapsing, and spacing between currency and amount.
- **AmountParserTests:** `1,250.00`, `1250`, `1,000,000.5`, plus rejection of `0`, empty input, and garbage.
- **ClassifierTests:** the OTP, promo, due-reminder, credit, and debit cases.
- **PipelineFixtureTests:** the full fixture corpus.
- **DedupTests:**
  - An identical body ingested twice results in 1 transaction and 1 `duplicate` status.
  - The same amount and account arriving 1 minute apart with different wording counts as a duplicate.
  - The same amount 10 minutes apart counts as 2 transactions.
- **IngestionServiceTests** (in-memory container):
  - A RawMessage is persisted even when parsing yields `.ignored`.
  - An Account is reused across two messages from the same card.
  - The failure path sets `failed` and does not throw.

---

### 13. Build and verification commands

```bash
brew install xcodegen          # once
xcodegen generate              # after any project.yml change
cd SpendCore && swift test     # parser + store tests on macOS
xcodebuild -scheme SpendSense -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Claude Code must keep `swift test` green and the app building for the simulator after every task.

---

### 14. Task order for Claude Code

Work in this order, and commit after each step with a conventional commit message.

1. `project.yml`, the app skeleton with 3 empty tabs, entitlements with the App Group, and the `SpendCore` package wired in. The app must build.
2. Models, `StoreFactory` (including file protection), and `TransactionStore`, plus an in-memory smoke test.
3. `Normalizer`, `AmountParser`, `MessageClassifier`, and their tests.
4. `ParserTemplate`, `TemplateLibrary`, `templates.json`, `TemplateParser`, and `GenericParser`.
5. `sms_samples.json` (20+ fixtures), `ParsingPipeline`, and `PipelineFixtureTests`. All must be green.
6. `IngestionService`, dedup, `DedupTests`, and `IngestionServiceTests`.
7. The Transactions, Messages, and Simulate tabs.
8. `LogTransactionFromSMSIntent` and `SpendSenseShortcuts`.
9. `README.md` with setup steps, including the manual device test in Section 15.

Stop and ask Pradeepa instead of guessing when:
- a requirement conflicts with Swift 6 concurrency rules in a way that forces changing a public API, or
- a new dependency seems necessary.

---

### 15. Manual acceptance test (Pradeepa, on a real iPhone)

Claude Code can't do these steps. They are listed so the README documents them.

1. Install on the device. Enable the App Group in the developer portal if Xcode asks.
2. **Simulate tab:** paste a sample and confirm it appears in Transactions.
3. **Shortcuts:**
   - Automation → + → **Message** → Message Contains `LKR`.
   - Turn on **Run Immediately** and turn off Notify When Run.
   - Add action **Log Transaction from SMS**. Set Message to *Shortcut Input → Content* and Sender to *Shortcut Input → Sender*.
   - Repeat the automation with the keyword `Rs` if your banks use it.
4. From another phone, text: `LKR 100.00 debited from card ending 4321 at TEST SHOP`. It should appear in the app without opening it.
5. **Lock the phone**, send another test SMS, then unlock. The transaction must be there, which verifies the file protection setting.
6. Send an OTP-style message. It should appear in the Messages tab as `ignored` and must not appear in Transactions.
7. Send the same message twice. The second one should be marked `duplicate`.

### 16. Definition of done
- All tests pass with `swift test`, and the app builds for the simulator with zero warnings under strict concurrency.
- Steps 2–7 of the manual acceptance test pass on a real device.
- No code path writes a Transaction without a linked RawMessage when `source == .sms`.
