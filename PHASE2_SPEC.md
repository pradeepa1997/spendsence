# SpendSense — Phase 2 Spec: make it useful

Phase 1/1.5 get bank SMS into the app reliably. Phase 2 makes the data usable day to day.

## Scope
1. **Categories.** 13 default categories, seeded automatically and editable (name, icon, colour). System categories
   can be renamed but not deleted. User categories can be added and deleted.
2. **Auto-categorisation** at ingest, in priority order:
   1. a **merchant rule** the user taught (longest matching pattern wins),
   2. credits → *Income*, transfers → *Transfers*,
   3. the **built-in keyword map** (KEELLS → Groceries, UBER EATS → Dining, UBER → Transport, DIALOG → Bills, …),
   4. *Other*.
   Existing uncategorised transactions are back-filled on launch.
3. **Edit transactions** (amount, type, merchant, category, date, note). After a merchant rename or category change
   the app offers: *Remember for future messages*, *Remember and update past transactions*, or *Just this one*.
   That creates/updates a `MerchantRule` (rename and/or category), which is applied to future SMS at ingest.
4. **Review queue** tab: low-confidence transactions not yet reviewed, plus SMS that couldn't be read
   ("no amount"). Actions: approve, edit, mark as not a transaction, add manually from the SMS, dismiss.
5. **Manual / cash entry**: an add sheet (amount, expense/income/refund/transfer, description, category, account or
   Cash, date, note) and a Siri / Shortcuts **Add Expense** intent.
6. **Dashboard** tab (Swift Charts): month picker, spent / income / net, spending-by-category donut with legend,
   daily bars, top 5 merchants, review chip, automation health banner. A **Monthly Spend** Siri intent.
7. **Transactions** tab: search (merchant, category, note, amount), category icons, swipe to approve or delete,
   + button for manual entry.
8. **More** tab: Categories, Merchant rules, Messages (debug), Simulate (debug).

Out of scope (Phase 3+): budgets, notifications, widgets, onboarding, on-device LLM, template builder, export.

## Data model changes (lightweight migration)
- New `TransactionCategory`: id, name, symbol, colorHex, isSystem, systemKey, sortOrder, excludedFromSpending.
  (Not named `Category`: that clashes with the Objective-C runtime typedef imported by Foundation.)
- New `MerchantRule`: id, pattern (merchant key), renameTo?, category?, hitCount, createdAt.
- `Transaction`: `+category`, `+originalMerchant` (as parsed; rules match on this), `+note`, `+isReviewed`,
  `+categoryIsManual`; `−categoryName` (Phase 1 placeholder, never populated).
- `Account`: manual entries without an account use a single **Cash** account.

## Spending maths (`SpendingSummary`, pure)
- Spent = debits − refunds, in LKR, excluding categories with `excludedFromSpending` (Transfers — ATM withdrawals and
  own-account transfers would otherwise double count cash spending).
- Income = credits (not in excluded categories).
- Other currencies are counted separately and not mixed into LKR totals.

## Write paths (the rule from Phase 1, extended)
- SMS → `IngestionService.ingest` only.
- User edits and manual entries → `TransactionEditor` (SpendCore), run on the view's main context so lists refresh
  immediately; Siri intents reach the same editor through `IngestionService.addExpense`.
- Views never mutate models directly.

## Tests
Categoriser (keywords, rules, precedence), merchant keys, spending summary maths, editor flows (rules applied to
future and past transactions, not-a-transaction, manual cash entry, category deletion), seeding idempotency,
ingest-time categorisation and rename.
