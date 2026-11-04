# SpendSense

An iOS expense tracker that logs bank SMS automatically. iOS doesn't let apps read the SMS inbox, so a
**Shortcuts personal automation** ("Message contains `LKR`") passes each bank SMS to the app's
**App Intent**. The intent parses the message and saves it on-device without opening the app.

Phase 1 covers the ingestion pipeline and three debug tabs. See `PHASE1_SPEC.md` for the full spec.

## Requirements
- Xcode 26, Swift 6 (strict concurrency)
- iOS 17+ (physical iPhone for the automation; the Simulator can't receive SMS)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- No third-party dependencies

## Setup
```bash
brew install xcodegen          # once
xcodegen generate              # after any project.yml change (the .xcodeproj is gitignored)
open SpendSense.xcodeproj
```
1. In Xcode → target **SpendSense** → *Signing & Capabilities*, pick your team.
2. The bundle ID is `com.pradeepa.spendsense` and the App Group is `group.com.pradeepa.spendsense`.
   If you change them, update `project.yml` **and** `SpendCoreInfo.appGroupIdentifier`
   (`SpendCore/Sources/SpendCore/SpendCore.swift`).
3. If Xcode asks, let it register the App Group in the developer portal.

## Build & test
```bash
cd SpendCore && swift test     # parser + store tests on macOS
xcodebuild -scheme SpendSense -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
CI (`.github/workflows/ci.yml`) runs both on a macOS runner.

## Architecture
```
Shortcuts automation ──► LogTransactionFromSMSIntent ─┐
Simulate tab ─────────────────────────────────────────┴─► IngestionService.ingest   (the only write path)
                                                             1. persist RawMessage (pending)
                                                             2. ParsingPipeline: normalize → classify →
                                                                template → generic → confidence
                                                             3. ignored → status only
                                                             4–5. TransactionStore.commit: dedup + upsert
                                                                Account + save Transaction (atomic)
                                                             6. any error → status failed, never throws
```
- `SpendCore/Sources/SpendCore/Parsing`: pure, `Sendable`, no SwiftData.
- `SpendCore/Sources/SpendCore/Resources/templates.json`: bank templates as data.
- `SpendCore/Tests/SpendCoreTests/Fixtures/sms_samples.json`: the test corpus (27 synthetic samples).
- Store: `<App Group>/Store/SpendSense.store`, directory protection
  `completeUntilFirstUserAuthentication`, so writes work while the phone is locked.

## Adding a real bank (TODO for Pradeepa)
1. Add real anonymized SMS to `sms_samples.json`. Replace names, card/account digits, and reference
   numbers, and write the `expect` block you want.
2. Run `swift test`. Failing fixtures print their `id`.
3. Add or adjust a template in `templates.json` until it's green. Templates are matched against
   *normalized* text: whitespace is collapsed, and `Rs.`/`Rs`/`SLRs` become `LKR` followed by a space.
   Use named groups `amount` (required), `currency`, `merchant`, `last4`, `balance`, `date` + `dateFormat`.
4. Bump `ParsingPipeline.version` if outputs for existing messages change.

## Manual acceptance test (real iPhone)
1. Install on the device. Enable the App Group in the developer portal if Xcode asks.
2. **Simulate tab:** use *Load sample* (or paste an SMS) and tap *Ingest*. Confirm the transaction
   appears in Transactions.
3. **Shortcuts:**
   - Automation → **+** → **Message** → *Message Contains* `LKR`.
   - Turn on **Run Immediately** and turn off *Notify When Run*.
   - Add the action **Log Transaction from SMS**. Set *Message* to *Shortcut Input → Content* and
     *Sender* to *Shortcut Input → Sender*.
   - Repeat with the keyword `Rs` if your banks use it.
4. From another phone, text `LKR 100.00 debited from card ending 4321 at TEST SHOP`. It should appear
   in the app without you opening it.
5. **Lock the phone**, send another test SMS, then unlock. The transaction must be there. This
   verifies the file protection setting.
6. Send an OTP-style message (`Your OTP is 123456. Do not share it.`). It should appear in Messages
   as *Ignored* and not in Transactions.
7. Send the same message twice. The second should be marked *Duplicate*.

You can also run the intent by hand: Shortcuts → new shortcut → *Log Transaction from SMS* → type a
message → ▶︎.

## Design decisions & deviations from the spec
| Topic | Decision | Why |
|---|---|---|
| "credit card" / "debit card" | Neutralized before verb detection (also "credit limit", "minimum payment", "payment due") | "spent on your credit card" must be a debit, not a credit |
| OTP keywords | Ignored **unless** a completed verb (`debited`, `credited`, `spent`, …) is present | Some banks append "never share your OTP" to real debit alerts |
| Promo keywords | Ignored only when no debit/credit verb is present (spec said this for `reward points`; applied to all promo words) | Avoid dropping real transactions that carry a marketing footer |
| Amount but no verb | Classified as `.transaction`; the generic parser subtracts 0.15 confidence, so it lands in `needsReview` | Spec required a fixture for this case but the classifier rules gave it no path |
| Credit vs debit when both verbs appear | Refund/reversal wording → `.refund`; otherwise whichever verb comes first | "Txn … reversed" must be a refund |
| Date-only SMS dates | Day from the SMS, time of day from `receivedAt`; implausible dates (> 1 day ahead or > ~13 months back) fall back to `receivedAt` | Midnight timestamps would make same-day purchases collide in the ±3 min dedup window and catch dd/MM vs MM/dd mistakes |
| Generic amount | Skips amounts directly preceded by `bal`/`balance`/`limit`/`due`; requires a leading digit | Avoids logging the balance as the spend |
| Generic merchant | Skips candidates starting with `your`/`a/c`/`account`/`card`; stops at more connector words (`using`, `for`, `credited`, …) | "credited to your A/C" isn't a merchant |
| Generic `last4` | Takes the *last* 4 digits of a digit run | Full account numbers |
| Bank name for generic matches | Template `bankName`, else SMS sender ID, else "Unknown Bank" | Needed for account matching and dedup |
| Body-hash dedup | Only earlier messages with status parsed/needsReview/duplicate block an identical body | A failed or ignored message must not swallow a retry |
| Dedup + save | One actor-isolated `TransactionStore.commit` call | Two automations firing at once can't both pass the check |
| Shared container | `SharedStore.containerResult` (lazy, in SpendCore); the app injects it and `IngestionService.shared` uses it | Guarantees one container per process |
| `upsertAccount` | Public on the store actor but only called inside it | `Account` isn't `Sendable`; returning it across actors would break Swift 6 rules |
| Confidence maths | Integer points ÷ 100 | `0.6 + 0.1 + 0.05` isn't exactly `0.75` in floating point |
| Duplicate summaries etc. | `Logged …`, `Logged for review: …`, `Ignored: …`, `Duplicate: … already logged`, `Failed: …` | |

## Known limitations (Phase 1)
- **iOS 17 list refresh:** on iOS 17.x, `@Query` sometimes doesn't refresh after a background
  `ModelActor` save. A row may briefly show *Pending* after Simulate until you switch tabs or
  relaunch. iOS 18+ isn't affected. Data is always saved correctly.
- Identical SMS bodies are always deduplicated. Two genuinely identical purchases whose SMS has no
  reference number or time will log once.
- The seed templates are illustrative shapes, not real bank formats.
