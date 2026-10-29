# 0003 — Development seed and every-page check

**Status:** Draft
**Date:** 2026-10-27

## Problem

To test the app by hand, a developer needs a phone full of realistic data: categorised
transactions, a Plan, debts, goals and loans. Today the only route is pushing SMS into the
emulator's inbox and tapping through the UI. That takes hours on a slow emulator, breaks easily,
and leaves most of the data uncategorised: on 27 Oct, Plan showed KES 290,314 under
Uncategorised and safe-to-spend showed "—". The SQLCipher key lives in the phone's Keystore, so
a ready-made database cannot be pushed from the computer; the seed has to run inside the app.
There is also no check that every page opens with real data before a build goes to someone for
testing.

## Goals / Non-goals

Goals:
- One command gives a profile build on the emulator that opens straight on Home with about
  three months of realistic data for a KES 150,000 net salary. Every page has content.
- The data goes through the app's own code paths: SMS parsing and ingest, payee naming,
  category confirmation, and the Plan, debt, goal and lending repositories.
- An automated check opens every page and main sheet with that data and fails on exceptions,
  layout overflows or missing data.
- None of this reaches release or CI builds.

Non-goals:
- Changing product behaviour. One production bug this work exposed (own-transfer pairing, see
  Open questions) is listed, not fixed.
- Maestro flows. The existing flows stay as they are; `maestro` and `timeout` are not installed
  on this Mac.

## Approach

### Entry point and guards
- `lib/main_dev_seed.dart`:
  1. `WidgetsFlutterBinding.ensureInitialized()`.
  2. `if (kReleaseMode) throw StateError(...)`.
  3. Create one `ProviderContainer` and read `appLockControllerProvider`.
  4. Wait until `keyReleased`. Running a query before then breaks the lazily opened database for
     the whole session.
  5. Skip seeding when a PIN is set.
  6. Call `seedDevData(container, now: DateTime.now())`.
  7. `runApp(UncontrolledProviderScope(container: c, child: const PesaClarityApp()))`.
- Seeding happens before `runApp`, so the providers computed once per session (`monthClose`,
  `planView`, `payday`, `insightsSummary`, `goalsOverview`, `lendingOverview`) see the data.
- It seeds only when there are no accounts and no `dev.seeded` row in app_settings, so
  reinstalling over a seeded app keeps its data and the person's changes.
- Code lives under `lib/src/dev/seed/` and is imported only by `lib/main_dev_seed.dart`, so it
  is compiled only with `-t lib/main_dev_seed.dart`. A new test, `test/dev/dev_import_guard_test.dart`
  in the style of `http_client_usage_test.dart`, fails if any other file imports `src/dev/`.
  The seed stays out of `lib/src/domain` (purity test), never calls `HttpClient(`, and never
  imports `pdfium_text_extractor.dart`, which `prepare_foss.sh` deletes.

### What the seed creates
Dates are computed from `now` in Nairobi time, and every `occurredAt` is ≤ `now`. The data runs
from the 1st of the month two months back (for example 1 Aug) up to today, so the health index
has a scored previous month, Insights has a trend, and Plan has closed months.

1. **Onboarding:** marked complete. M-Pesa, KCB and I&M are selected, and the current privacy
   policy is accepted, so no dialog blocks the first screen.
2. **SMS:** a deterministic Dart port of the generator used today, run through
   `SmsIngestor.ingest(..., parse: parseAll)`.
   - Net salary of KES 150,000 to KCB on the 25th.
   - Rent, the bank loan and savings leave from KCB; about 95,000 moves to M-Pesa.
   - Bills, groceries, lunches, transport, family, chama, Sacco, a school-fee one-off, medical,
     insurance, church, betting, shopping, entertainment, a house help, one reversal, Fuliza
     near month end with automatic repayment, and Upwork income.
   - I&M is used as savings.
   - Fixes over today's generator: balances stay consistent, Fuliza draws are stamped before the
     payment they fund, and phone numbers match `PayeeIdentifier.phone`.
3. **Own transfers:** `findOwnTransfers` plus `saveTransferPairs`, so the KCB-to-M-Pesa moves
   are not counted as spending.
4. **Categories:**
   - Name every recurring counterparty with `PayeesRepository.name(..., defaultCategoryId:)`.
     Some get a leak type, such as bars (lifestyle) and family support (family), so Insights
     shows leakages.
   - Rows with no counterparty (bank alerts, airtime, Fuliza, receipts with no phone) get
     `setOverride`.
   - About 10 rows go through `CategorySuggestionsRepository.confirm`, so corrections and
     confirmations exist for learning.
   - About 3 rows stay uncategorised on purpose, to test the suggestion sheet.
5. **Plan**, with recurring lines from the first seeded month:
   - Bills and income: Salary 150,000 (25th); Rent 35,000 (1st); Bank loan 12,450 (5th);
     Electricity, water and internet 7,500 (3rd); House help 9,000 (5th); Mum 8,000 (26th);
     Sacco 10,000 (26th); Insurance 4,200 (10th); Church 4,000 (4th).
   - Day-to-day budgets: groceries 18,000, eating out 8,000, transport 5,000, airtime 1,500,
     friends 4,000, lifestyle 2,000.
   - A one-off school-fee line this month.
   - Past bills are paid by matching categorised transactions, except one deliberately short
     electricity payment two months back, so exactly one arrear shows.
6. **Debts:** a KCB personal loan (180,000, 12,450 a month, linked to the KCB debits) and a
   family loan (30,000, instalments of 5,000), with the avalanche strategy saved. Fuliza is
   tracked from the messages.
7. **Goals:** Emergency fund (300,000 target, 85,000 saved, June next year) and New laptop
   (120,000 target, 40,000 saved).
8. **Lending:** 5,000 lent to Kevin, due on the 15th and now overdue; 2,000 lent to Faith with
   1,000 repaid, due next month.
9. **Tags:** "Work" on some lunches and "Wedding" on two purchases.
10. **Payday:** tasks left unticked, so the banner and page show on payday weeks.

### Every-page check
- **Host test `test/widget/every_page_test.dart`** (runs in `flutter test`, CI included).
  - Uses the existing `pumpApp` harness with an in-memory database and a fixed clock (27 Oct
    2026, 12:00 Nairobi), then runs the same `seedDevData`.
  - Visits all 23 routes: launch, the 4 onboarding routes on a separate unseeded pass, 5 tabs,
    import, profile, profile accounts, backup, backup setup, privacy, policy, payees, sign-in,
    payday, debts and lending.
  - Opens the main sheets: add menu, add transaction, transaction, category picker, payee, name
    payee, category suggestion, export, plan item, surplus split, debt, goal, loan, and loan
    actions.
  - For each it asserts `tester.takeException() == null`, no overflow `FlutterError`, and a
    data marker, for example: safe-to-spend shows a KES figure (not "—"), Plan by-category is
    not mostly Uncategorised, Activity shows "Naivas", Goals shows "Emergency fund", Debts shows
    the KCB loan, Lending shows Kevin as overdue, and Insights shows a leakage.
- **On-device tour before handover.** One pass, run only when nobody is using the emulator,
  with no polling loops:
  - Open each page once through its semantic id or title and take one screenshot.
  - Then scan logcat for `flutter` errors and `am_anr`.
  - I review the screenshots before handing the build over.

### How to run
```sh
~/Library/Android/sdk/emulator/emulator -avd Pesa_AOSP_34 -gpu swiftshader_indirect -noaudio &
flutter run --profile --no-enable-impeller --flavor foss -t lib/main_dev_seed.dart
```
To start again from fresh data, run `adb shell pm clear com.pesaclarity.app` and launch again.

## Alternatives considered

- **Push SMS into the emulator inbox and tap through the UI** (today's approach): slow, fragile,
  needs root and direct writes to the telephony database, and cannot categorise rows that have
  no tap target (airtime, Fuliza, own transfers). Rejected.
- **A hidden "Load sample data" button in debug builds:** it lives in the product UI, and the
  providers computed once per session would need invalidating. Rejected in favour of a separate
  entry point.
- **Write rows with raw SQL:** this skips parsing, payee resolution and dedupe, so it would not
  exercise the real paths. Rejected.
- **Maestro for the page check:** it needs a CLI that is not installed, and its flows only
  check titles. Kept as is; the widget test covers data and sheets.

## Changes

- New: `lib/main_dev_seed.dart`, `lib/src/dev/seed/sms_fixture.dart` (message generator),
  `lib/src/dev/seed/dev_seed.dart` (`seedDevData`), `test/widget/every_page_test.dart` and
  `test/dev/dev_import_guard_test.dart`.
- No change to `lib/main.dart`, the manifests, pubspec assets or CI workflows.

## Acceptance criteria

- [ ] A release build (`flutter build apk --release --flavor foss`) contains no `src/dev` code.
      Checked with `--analyze-size` or by grepping the AOT snapshot for `seedDevData`.
- [ ] `flutter analyze --fatal-infos`, `dart format` and the whole `flutter test` suite pass,
      including `every_page_test.dart`.
- [ ] On a fresh install with the run command above, the app opens on Home with a KES
      safe-to-spend figure, a health index and a forecast. Plan shows categorised spending with
      one arrear; Activity, Goals, Debts, Lending, Payees and Insights all show seeded data.
- [ ] Launching again does not seed twice: the number of transactions is unchanged.
- [ ] With a PIN set, the seed is skipped and the app opens normally.
- [ ] The on-device tour shows 0 `flutter` errors and 0 `am_anr` in logcat.

## Edge cases

- **A run on a day other than the 25th–31st:** the payday banner only shows within 7 days of
  salary, as in production. The test pins the clock.
- **The inbox already holds MPESA, KCB or I&M messages** (such as the ones pushed into the
  emulator today): live capture would add them on top. The seed is only meant for a clean
  inbox; today's pushed messages are deleted from the emulator before switching.
- **The seed fails halfway:** the `dev.seeded` marker is written last. Clear app data and run
  again.
- **Month boundaries:** dates come from Nairobi calendar helpers, never the emulator's time zone.

## Test plan

`every_page_test.dart` (above), `dev_import_guard_test.dart`, and a unit test that the
generator's balances are consistent and that every message parses with the bundled packs.
Manual: the on-device tour.

## Rollout & rollback

Dev-only, with no effect on users. Rollback: delete the new files.

## Open questions

1. **A production bug found while mapping:** own transfers are never paired after SMS ingest.
   `findOwnTransfers` and `saveTransferPairs` are only called from a test, so a real person's
   KCB-to-M-Pesa move counts as spending. The seed pairs them itself. Should I fix production
   ingest too, as a separate small spec?
2. **Airtime, Fuliza and own-transfer rows** collapse into lines in Activity that cannot be
   tapped, so a person cannot categorise them. Is that intended?
