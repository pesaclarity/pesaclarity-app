# 0001 — Categorise transactions automatically

**Status:** Draft
**Date:** 2026-10-27

## Problem

Every imported transaction stays Uncategorised until the person picks a category by hand. The
suggester (`CategorySuggester`) already produces good guesses (the person's own earlier choice for
the payee, then the rules or an installed model), but they are only shown as chips in Activity and
never applied. So Plan's "By category" shows the whole month under Uncategorised (KES 290,314 of
0 in the October test data), safe-to-spend sees no day-to-day spending, and Insights and the
Health Index work from nothing.

The learning half is also unbuilt: `onDeviceTrainerProvider`, `federatedUpdateTrainerProvider`
and `modelUpdateUploaderProvider` are `null`, and no code downloads a model, so every phone runs
`RuleCategoriser` for good.

## Goals / Non-goals

Goals (this spec):
- Apply a category automatically when the app is confident, so Plan, safe-to-spend and Insights
  work from the first scan.
- Learn from the person's past transactions: once they set a category for a payee, every
  earlier and later transaction from that payee that they have not set themselves follows it.
- Keep machine guesses separate from the person's choices, shown as "Auto" and fixable in one tap.
- Leave clean hooks for the federated model (phases 2 and 3 below), so they plug in without
  touching this logic again.

Non-goals (this spec):
- Downloading a model from the Pesa Clarity organisation (phase 2, own spec).
- On-device fine-tuning and DP-FedAvg updates (phase 3, own spec). Both need work outside this
  repo: a trainable TFLite export with train/infer signatures from pesaclarity-ml, and an
  aggregator in pesaclarity-backend.
- Changing the rules or the category list.

## Approach

Store the machine's choice next to the person's, and resolve in one place.

1. **Schema (v10 → v11).** Add three nullable columns to `transactions`:
   `auto_category_id` (FK to categories, `ON DELETE SET NULL`), `auto_category_source`
   (`SuggestionSource`: correction, rules, model) and `auto_category_confidence` (real).
2. **Resolution.** The effective category becomes
   `categoryOverrideId ?? payee.defaultCategoryId ?? autoCategoryId`, in `applyPayee` (the one
   function that already resolves it). `LedgerEntry` gains `categoryIsAuto`, true only when the
   auto column decided it. Everything downstream (Plan, safe-to-spend, Health, Insights, export)
   reads `LedgerEntry.categoryId`, so it all picks this up unchanged.
3. **Auto-apply rule.** `CategorySuggester.suggest` is unchanged. A new
   `autoApplies(suggestion)` decides:
   - the person's own earlier choice for the payee (`correction`, confidence 1): always;
   - rules or model at or above `autoApplyConfidence = 0.6`: apply. Today that means message-type
     rules (airtime, Fuliza repayment, charges at 0.9) and known payees (Naivas, KPLC, Zuku... at
     0.6);
   - below 0.6 (for example "money received" at 0.4): stays a suggestion chip, as now.
4. **`AutoCategoriser` service** (`features/categoriser/application/auto_categoriser.dart`).
   It walks transactions that have no override and no payee default, runs the suggester, and
   writes the auto columns. It writes only rows whose result changed, and clears the columns
   when nothing qualifies any more. It is triggered:
   - after each SMS ingest or statement import, for the new rows;
   - after `confirm()`, for every transaction from the same payee (this is "learning from past
     transactions": one choice fixes the history and the future);
   - when the installed categoriser changes (phase 2 model arrives), for all rows;
   - once after the v11 migration, for existing data.
   It runs in batches of 200 inside a transaction per batch, off the UI frame. It is idempotent,
   so a re-run after a crash finishes the job.
5. **UI.** Where a category name shows (Activity row, transaction sheet, Plan drill-down), an
   auto one gets a small "Auto" tag. Tapping it opens the existing picker. Picking the same
   category confirms it; it is logged in `category_confirmations` as an accepted suggestion and
   becomes training data. Picking another category is a correction. Unconfident suggestions keep
   today's chip.
6. **Learning stays honest.** Training examples still come only from `category_confirmations`
   (the person's choices), never from auto rows, so the model is not trained on its own guesses.

### Phases 2 and 3 (federated learning), for context

- **Phase 2, organisation model.** A `ModelDownloader` fetches `model-manifest.json`, `labels.json`
  and the `.tflite` file from the Pesa Clarity API through `HttpClientFactory` (pinned), verifies
  an organisation signature plus the existing SHA-256 and size checks in `loadCategoriser`, and
  swaps it in. `AutoCategoriser` then re-runs on all non-person rows. Needs a release channel
  and a signing key from pesaclarity-ml and pesaclarity-backend.
- **Phase 3, federated learning.** With "Help improve the app" on (`improveAppOptInProvider`, which
  exists), fine-tune on the phone from confirmations and compute a clipped, noised DP-FedAvg
  delta (`FederatedUpdateTrainer`). Upload it with an integrity token (`IntegrityAttestor`
  already supplies the header) to the aggregator, which folds the deltas into the next
  organisation model shipped in phase 2. Raw payees and amounts never leave the phone; only
  encoded-feature weight deltas do.

## Alternatives considered

- **Write auto choices into `categoryOverrideId`.** No migration, but the app could no longer
  tell the person's choice from its own guess. A better model could never fix old guesses, and
  the model would train on its own output. Rejected.
- **Resolve at read time (run the suggester inside `ledgerEntries`).** No new columns, but the
  suggester depends on the loaded TFLite model and the corrections stream, which the data layer
  should not reach into. It would run on every query in every screen, which is slow on 2 GB
  phones. Rejected.
- **Set the payee's default category automatically.** Simple, but it turns a guess into a rule
  the person did not make, and payee defaults apply even to transactions the person has
  already overridden elsewhere. Rejected; payee defaults stay a deliberate choice.

## Changes

- `lib/src/data/database/tables.dart`: three columns on `Transactions`. **Migration v10→v11**
  in `app_database.dart` (`addColumn` ×3), then a regenerated `app_database.g.dart`.
- `lib/src/domain/payees/payee_directory.dart`: `applyPayee` takes `autoCategoryId` and returns
  `isCategoryAuto`.
- `lib/src/domain/ledger/ledger_entry.dart`: `categoryIsAuto` field.
- `lib/src/domain/categoriser/suggester.dart`: `autoApplyConfidence` and `autoApplies()`.
- `lib/src/data/repositories/transactions_repository.dart`: map the new columns; add
  `setAutoCategories(List<AutoCategory>)` (batched, writes only what changed) and
  `uncategorisedIds({payeeKeys, ids})`.
- `lib/src/data/repositories/category_suggestions_repository.dart`: `confirm()` unchanged in what
  it stores; the caller then triggers a payee back-fill.
- `lib/src/features/categoriser/application/auto_categoriser.dart` (new) plus a provider;
  wired into `SmsIngestor`, statement import, `confirm` callers, and `loadedCategoriserProvider`
  changes.
- `lib/src/data/repositories/export_repository.dart`: export the effective category, plus a
  `category_source` column (person, payee, auto).
- Activity row, transaction sheet and Plan category drill-down: the "Auto" tag.
- Check that `.pcbackup` round-trips the new columns (the backup codec serialises tables).

## Acceptance criteria

- [ ] After a first scan of the October test data, Plan shows groceries, eating out, transport,
      utilities, airtime and Fuliza repayment spending under their categories, not
      Uncategorised.
- [ ] A transaction the person categorised is never changed by `AutoCategoriser`.
- [ ] A transaction whose payee has a default category shows the payee's category, not an auto one.
- [ ] Setting a category on one transaction from "MAMA MBOGA WANJIRU" categorises every other
      transaction from that payee that is not person-set, past and future, within one second.
- [ ] Suggestions below 0.6 are not applied and still show as a chip.
- [ ] Auto categories show an "Auto" tag; person and payee ones do not.
- [ ] Accepting an auto category adds an accepted row to `category_confirmations`; auto rows alone
      add none.
- [ ] Own transfers, reversals, borrowing and unnamed senders get no auto category.
- [ ] A v10 database upgrades to v11 without losing data and gets back-filled on first launch.
- [ ] Export and backup carry the effective category and its source.

## Edge cases

- **Category deleted:** `ON DELETE SET NULL` clears the auto column, and the next run picks again.
- **Correction changes its mind:** the back-fill rewrites only auto rows, so earlier person-set
  rows keep their own value.
- **Same payee, money in and out:** the suggester's `_fits` keeps income categories off outflows
  and the reverse; a correction that does not fit the direction is skipped, as today.
- **Model refused or missing:** the rules apply, and auto rows from an old model are re-scored on
  the next full run.
- **Crash mid-run:** batches commit one at a time; the run is idempotent and repeats on the next
  trigger.
- **Large history (5 years, about 30k rows):** batches of 200, written only on change. A first
  back-fill of about 30k rows on a low-end phone is expected to take seconds, in the background.
- **Concurrent triggers:** one run at a time (queued, like `SmsScanService`); a pending trigger
  merges into the next run.

## Test plan

- Unit `test/domain/categoriser/suggester_test.dart`: `autoApplies` at 0.59, 0.6 and correction.
- Unit `test/domain/payees/payee_directory_test.dart`: resolution order override > payee > auto.
- Database `test/data/auto_categoriser_test.dart`: first run categorises Naivas, KPLC and airtime;
  leaves "money received" alone; does not touch person-set rows; back-fills a payee after
  `confirm`; clears when the category is deleted; second run writes nothing.
- Database `test/data/app_database_test.dart`: v10 → v11 migration keeps rows.
- Widget `test/widget/home_activity_test.dart`: Activity shows "Auto"; picking the same category
  removes the tag and logs a confirmation.
- Manual: the October seed on the emulator; Plan and safe-to-spend show categorised spending.

## Rollout & rollback

Ships in the next debug and release builds, with no flag: the behaviour is visible and correctable
in one tap. Rollback: a release that ignores `auto_category_*` in `applyPayee` reverts behaviour
with no migration (the columns stay, unused). Person choices are never touched, so nothing needs
repair.

## Open questions

1. Is a 0.6 auto-apply threshold right? It applies known-payee rules (Naivas → Groceries). At 0.7
   only message-type rules and the person's own choices would apply.
2. Should the "Auto" tag show everywhere or only in the transaction sheet? The proposal shows it
   in Activity too, so people can scan and fix.
3. Phases 2 and 3 need pesaclarity-ml (a trainable export and a signing key) and
   pesaclarity-backend (model release and aggregator endpoints). Are those planned, and should I
   write their specs next?
