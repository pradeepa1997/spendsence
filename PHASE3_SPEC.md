# SpendSense — Phase 3 Spec: polish

## 1. Budgets
- Optional **monthly budget per category** (`TransactionCategory.monthlyBudget`).
- `BudgetCalculator` (pure): for a month's `SpendingSummary`, each budgeted category's spent, remaining, fraction
  and level: `ok` (< 80%), `warning` (≥ 80%), `over` (≥ 100%).
- **Budgets** screen (More → Budgets and a Dashboard card): progress bars for the current month, set/clear budgets.
- **Alerts** at 80% and 100%, once per category per month per threshold (`BudgetAlertPlanner`, pure). Crossing
  straight past 100% sends only the 100% alert. Checked after every SMS, manual entry and edit.

## 2. Notifications (local only)
- After each logged SMS: "LKR 2,450.00 – Keells Super" / "Groceries · HNB ••4821".
  - Tap → opens the transaction. **Change category** → opens it for editing. **Not an expense** → removes it in the
    background (same as Review's "Not a transaction").
  - Low-confidence ones say "Tap to review".
- Budget alerts as above.
- Settings toggles for each kind; permission asked during onboarding.

## 3. Widgets (new `SpendSenseWidgets` extension, reads the App Group store)
- **Spending** — small: spent this month (+ budget used); medium: spent, income, top 3 categories with bars.
- **Lock screen** — rectangular (spent + top category), circular (overall budget gauge, or spent), inline.
- **Quick add** — small widget that opens the Add transaction sheet.
- Timelines refresh every 30 minutes and whenever the app/intents change data (`WidgetCenter.reloadAllTimelines`).

## 4. Onboarding (first launch, re-runnable from Settings)
1. Welcome + privacy promise.  2. Supported banks + which keyword to use (LKR / Rs).
3. Step-by-step Shortcuts automation setup with an "Open Shortcuts" button.
4. **Verify**: waits for the first SMS from the automation and shows the result.  5. Notifications permission.
Existing users who already have automation messages skip it automatically.

## 5. Deep links
`spendsense://add`, `spendsense://transaction/<uuid>`, `spendsense://dashboard`, `spendsense://review`,
`spendsense://budgets` — used by widgets and notifications.

## 6. Shared snapshot
`DashboardSnapshot.load(in:now:)` (SpendCore) builds what widgets and Siri need (month totals, top categories,
budgets, review count) from any `ModelContext`.

## Tests
Budget levels and remaining, alert planning (once per threshold, 100% supersedes 80%, month keys), dashboard
snapshot, compact amount formatting, "not an expense" by id, budget validation.
