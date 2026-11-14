# SpendSense — Phase 2.5 Spec: accounts and balances

Accounts are already created automatically from SMS (bank + last digits). Phase 2.5 makes them first-class:
it knows what each account is, tracks its balance, and lets the user tidy them up.

## 1. Account types
`AccountKind`: `bankAccount`, `debitCard`, `creditCard`, `cash`, `unknown`.

- Each template declares the kind it reads (`accountKind` in `templates.json`):

  | Template | Kind | What the SMS balance means |
  |---|---|---|
  | `hnb_card_alert` | debitCard | account balance (`Av.Bal`) |
  | `hnb_account`, `dfcc_account`, `seylan_account`, `peoples_account` | bankAccount | account balance |
  | `dfcc_card`, `ndb_card`, `seylan_card` | creditCard | **available credit** (`AVBAL` / `Avl Bal`) |

- The generic parser infers it from the wording ("credit card" → creditCard, "debit card" → debitCard,
  "A/C"/"account" without "card" → bankAccount).
- Detection refines but never overrides the user: unknown → detected; debitCard → bankAccount when an account SMS for
  the same account arrives (HNB card alert + account SMS share one account); a kind set by the user is kept.
- The Cash account (manual entries) is `cash`.

## 2. Balances (`BalanceCalculator`, pure)
Every account has a timeline of events, oldest first: each transaction (its effect, plus the balance the SMS reported,
if any) and the user's latest "Set balance". Walking the timeline:
- a reported or manual balance **resets** the running balance,
- a transaction without a reported balance **adjusts** it: debit/transfer −, credit/refund +,
- Cash starts from 0 (until the user sets an opening balance).

Result: current value, as-of date, source (`reported` / `manual` / `computed`), `pendingCount` (transactions since the
last reported/manual balance → shown as *estimated*), and a history for a chart.

Credit cards: the value is **available credit** (same arithmetic: purchases reduce it, payments/refunds increase it).
With a credit limit set by the user, **owed = limit − available** and utilisation = owed ÷ limit.

## 3. Account management (`TransactionEditor`)
- Edit: display name, kind, credit limit (credit cards), low-balance alert threshold, hidden.
- Set balance (e.g. opening cash or a correction); clear it again.
- **Merge** account A into B: A's transactions move to B, B keeps the longest card ending, and A's (bank, ending) is
  remembered as an alias so future SMS for A land in B. Dedup and account matching honour aliases.

## 4. UI
- **Accounts** screen (Dashboard card and More → Accounts): totals (money in accounts, owed on cards), sections for
  bank accounts & debit cards, credit cards, cash, hidden. Rows show balance and "as of …" or "estimated".
- **Account detail**: balance header, balance chart, credit limit/owed/utilisation, details, recent transactions,
  Set balance, Edit, Merge into…
- **Dashboard**: accounts card with totals and low-balance warnings.

## 5. Migration
New `Account` fields have defaults (lightweight migration). On launch, `prepare()` marks the existing Cash account as
`cash`; other existing accounts pick up their kind from the next SMS (or the user sets it).
`ParsingPipeline.version` → 3.

## 6. Tests
Template kinds, generic inference, kind refinement rules, balance timelines (reported, estimated, manual, cash,
credit card owed), merge + aliases at ingest, editor validation.
