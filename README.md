# SpendSense

An iOS expense tracker that logs bank SMS automatically. iOS doesn't let apps read the SMS inbox, so a
**Shortcuts personal automation** ("Message contains `LKR`") passes each bank SMS to the app's
**App Intent**. The intent parses the message and saves it on-device without opening the app.

Specs: `PHASE1_SPEC.md` (SMS ingestion), `PHASE2_SPEC.md` (categories, editing, review queue, dashboard),
`PHASE2_5_SPEC.md` (accounts and balances) and `PHASE3_SPEC.md` (budgets, notifications, widgets, onboarding).

## Features
- **Dashboard:** spent / income / net for any month, a spending-by-category donut, daily bars, top merchants,
  a review chip and an automation health warning.
- **Transactions:** search, category icons, swipe to approve or delete, **+** for cash or manual entries.
- **Edit and teach:** fix any field. After renaming a merchant or changing a category, choose *Remember for future
  messages* or *Remember and update past transactions*. That becomes a merchant rule (More → Merchant rules).
- **Review:** low-confidence transactions and SMS the app couldn't read. Approve, edit, mark as not a transaction,
  add manually or dismiss.
- **Categories:** 13 defaults, auto-assigned (your rules → built-in keywords such as KEELLS → Groceries, UBER EATS →
  Dining, DIALOG → Bills → Other; credits → Income). Rename, restyle or add your own under More → Categories.
  Transfers (ATM withdrawals, own-account transfers) aren't counted as spending.
- **Accounts & balances** (Dashboard card, More → Accounts & balances): accounts and cards are detected from SMS with
  their type (bank account, debit card, credit card, cash). Balances come from the latest SMS that states one;
  later transactions without a balance adjust it (shown as *estimated*). Credit cards show available credit and, with
  a limit, what you owe. Set balance, low-balance alerts, hide, and merge duplicate accounts.
- **Budgets** (More → Budgets, Dashboard card): a monthly budget per category with progress bars; notifications
  at 80% and 100% (once per category per month).
- **Notifications:** one per logged SMS ("LKR 2,450.00 – Keells Super", "Groceries · HNB ••4821") with
  *Change category* and *Not an expense* actions. Toggle them in More → Settings.
- **Widgets:** Spending (small/medium), Lock Screen (rectangular/circular/inline) and Quick add.
- **Onboarding:** a first-launch guide for the Shortcuts automation that waits for your test SMS. Re-run it from
  More → Settings.
- **Siri / Shortcuts:** "Log SMS in SpendSense" (the automation action), "Add expense in SpendSense",
  "How much did I spend in SpendSense".

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

## Targets
- `SpendSense` (app, App Intents) and `SpendSenseWidgets` (WidgetKit extension, embedded in the app). Both use the
  App Group `group.com.pradeepa.spendsense` and link `SpendCore`.
- When signing, pick your team for **both** targets. The widget bundle ID is `com.pradeepa.spendsense.widgets`.
- Deep links: `spendsense://add`, `spendsense://transaction/<uuid>`, `spendsense://dashboard`, `spendsense://review`,
  `spendsense://budgets`.

## Build & test
```bash
cd SpendCore && swift test     # parser + store tests on macOS
xcodebuild -scheme SpendSense -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
CI (`.github/workflows/ci.yml`) runs both on a macOS runner.

## Architecture
```
Shortcuts automation ──► LogTransactionFromSMSIntent ─┐
Simulate tab ─────────────────────────────────────────┴─► IngestionService.ingest   (the only SMS write path)
                                                             1. persist RawMessage (pending)
                                                             2. ParsingPipeline: normalize → classify →
                                                                template → generic → confidence
                                                             3. ignored → status only
                                                             4–5. TransactionStore.commit: dedup + upsert
                                                                Account + save Transaction (atomic)
                                                             6. any error → status failed, never throws
```
- At step 5 the transaction is categorised (`CategoryService` → `Categorizer`) and renamed by any merchant rule.
- User edits, manual entries, categories and rules go through `TransactionEditor` on the view's main context;
  Siri's Add Expense reaches the same editor via `IngestionService.addExpense`.
- `SpendCore/Sources/SpendCore/Parsing`: pure, `Sendable`, no SwiftData.
- `SpendCore/Sources/SpendCore/Resources/templates.json`: bank templates as data.
- `SpendCore/Tests/SpendCoreTests/Fixtures/sms_samples.json`: the test corpus (38 samples: 27 synthetic, 11 anonymized real bank formats).
- Store: `<App Group>/Store/SpendSense.store`, directory protection
  `completeUntilFirstUserAuthentication`, so writes work while the phone is locked.

## Supported banks
| Bank | Formats | Template id |
|---|---|---|
| HNB | Debit card alert (`HNB SMS ALERT:…`), account credit/debit (`… credited to Ac No:…`) | `hnb_card_alert`, `hnb_account` |
| DFCC | Credit card (`ALERT CR CARD:…`), account (`Your A/C No: … is debited with …`) | `dfcc_card`, `dfcc_account` |
| NDB | Credit card (`Card 4815…**** Debited …`) | `ndb_card` |
| Seylan | Account (`Your Account … was credited by …`), card (`Seylan Card …0734 debit Txn …`) | `seylan_account`, `seylan_card` |
| People's Bank | Account (`Your A/C 335-… has been debited by Rs. …`) | `peoples_account` |

Three `generic_*` placeholder templates from Phase 1 remain as a last resort. Account endings with only 2 visible
digits (HNB, People's Bank) are matched to the same account as a longer ending, e.g. `…95` and `…7795`.

## Automation health & cleanup
- The Transactions tab shows a warning when no SMS has arrived from the automation for more than 5 days
  (`AutomationHealth`). Simulate-tab messages don't count.
- Ignored messages (OTPs, promotions, reminders) are deleted 7 days after they arrive, each time the app becomes active.

## Adding a real bank (TODO for Pradeepa)
1. Add real anonymized SMS to `sms_samples.json`. Replace names, card/account digits, and reference
   numbers, and write the `expect` block you want.
2. Run `swift test`. Failing fixtures print their `id`.
3. Add or adjust a template in `templates.json` until it's green. Templates are matched against
   *normalized* text: whitespace is collapsed, and `Rs.`/`Rs`/`SLRs` become `LKR` followed by a space.
   Use named groups `amount` (required), `currency`, `merchant`, `last4` (last 2–4 visible digits), `balance`,
   `date` + `dateFormat`, and `time` + `timeFormat` (e.g. `HH:mm`, `hh:mm:ss a`). Month names parse in any case.
   Fixtures can set `receivedAt` (ISO-8601) and `expect.occurredAt` (`yyyy-MM-dd HH:mm`, local time).
4. Bump `ParsingPipeline.version` if outputs for existing messages change.

## Manual acceptance test (real iPhone)
1. Install on the device. Enable the App Group in the developer portal if Xcode asks.
2. **More → Simulate SMS:** use *Load sample* (or paste an SMS) and tap *Ingest*. Confirm the transaction
   appears in Transactions, with a category.
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
   as *Ignored* (More → Messages) and not in Transactions.
7. Send the same message twice. The second should be marked *Duplicate*.
8. **Phase 2:** edit a transaction's merchant or category and choose *Remember…*; send a similar SMS and check the
   rule is applied. Add a cash expense with **+** and with Siri ("Add expense in SpendSense"). Check the Dashboard
   totals and the Review tab badge.
9. **Phase 3:** set a budget below what you've spent and send a test SMS: you should get the logged notification and
   a budget alert. Try *Not an expense* on a notification. Add the Spending and Lock Screen widgets and check they
   update after an SMS. Reinstall (or More → Settings → Show the setup guide again) to walk through onboarding.

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
| Amount after currency | `570.47 LKR` counts as an amount for classification | HNB card alerts have no verb and put the code after the number |
| Account endings | Templates keep 2–4 digits; a short ending matches a longer one of the same bank, and the account keeps the longest | HNB and People's Bank mask all but 2 digits |
| Card descriptors | A trailing province code (`WPLK`) is dropped and a repeated word collapsed | `CIBMART PILIYANDALA PILIYANDALA WPLK` → `Cibmart Piliyandala` |
| `RawMessage.sourceRaw` | New field (default `sms`, migrates automatically) | The health check must ignore Simulate-tab messages |
| Category model name | `TransactionCategory` | `Category` clashes with the Objective-C runtime typedef imported by Foundation |
| `Transaction.categoryName` | Replaced by a `category` relationship (+ `originalMerchant`, `note`, `isReviewed`, `categoryIsManual`) | Phase 2 categories; lightweight migration |
| Spending total | Debits − refunds, excluding the Transfers category; other currencies counted separately | ATM withdrawals and own-account transfers would double count |
| Rules on past transactions | Only when the user picks "update past"; transactions whose category was picked by hand keep it | Don't silently overwrite manual choices |
| Ingest contexts | `TransactionStore` uses a fresh `ModelContext` per operation | A long-lived background context kept stale copies of objects edited in the UI |
| Credit card "balance" | Stored and shown as available credit; owed = limit − available when a limit is set | Sri Lankan card SMS report available credit, not the outstanding amount |
| Foreign-currency transactions | Don't adjust LKR balances (a later SMS balance still resets) | No exchange rate on-device |
| Duplicate summaries etc. | `Logged …`, `Logged for review: …`, `Ignored: …`, `Duplicate: … already logged`, `Failed: …` | |

## Known limitations (Phase 1)
- **iOS 17 list refresh:** on iOS 17.x, `@Query` sometimes doesn't refresh after a background
  `ModelActor` save. A row may briefly show *Pending* after Simulate until you switch tabs or
  relaunch. iOS 18+ isn't affected. Data is always saved correctly.
- Identical SMS bodies are always deduplicated. Two genuinely identical purchases whose SMS has no
  reference number or time will log once.
- The seed templates are illustrative shapes, not real bank formats.
