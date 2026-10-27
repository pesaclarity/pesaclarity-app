# 0002 — Cut runtime overhead and stabilise emulator testing

**Status:** Draft
**Date:** 2026-10-27

## Problem

While the app was being tested on an x86_64 emulator, "System UI isn't responding" appeared every
few minutes, and Android's watchdog twice killed `system_server`. Evidence from the device:

- Idle, the app used about 1.2% CPU and drew 0 frames in a 21 s window. Nothing in the app runs
  in a loop: there are no periodic timers or polling, and the only timer is on the lock screen.
- 10 ANRs were logged on the Google APIs image. None was Pesa Clarity: 7 were Google Play
  services doing first-boot work, and 3 were System UI or `system_server`, starved on 2 vCPUs.
- The watchdog kill at 17:59 was the window manager blocked 88 s in
  `ScreenCapture.captureLayers` (a task snapshot during a launch transition), with the app
  rendering through Impeller on SwiftShader.
- The debug build: RSS 514 MB (about 260 MB Dart JIT heap, about 214 MB mapped APK), and the
  APK is 237 MB. The profile build: RSS 224 MB, and the APK is 70.7 MB.
- The host Mac throttles to 22–51% CPU speed when hot.

So the emulator freezes come mostly from the test setup, not the app. A review of 89 agents
(30 findings verified, 11 refuted) still found five places where the app does avoidable work in
bursts.

## Goals / Non-goals

Goals:
- Remove the avoidable bursts of work the review confirmed (A1–A5), with no visible change.
- One documented-in-code, light way to run the app on an emulator (B1), used by the dev seed (0003).

Non-goals:
- Changing release or real-device rendering. Impeller stays on in all manifests.
- Debouncing `ledgerChangesProvider`: it adds latency to every edit and breaks two tests;
  Riverpod pausing already merges bursts.
- A schema change or new indexes.

## Approach

App code. Each change is behaviour-preserving and comes from the verified findings:

- **A1. SMS ingest writes in one transaction per batch.** Add `ReviewInboxRepository.addAllIfNew`.
  In `TransactionsRepository.addNew`, replace the check-then-insert with
  `insertReturningOrNull(..., onConflict: DoNothing(target: [accountId, dedupeKey]))`.
  The conflict targets are the existing unique indexes, so duplicates are still skipped and the
  counts are unchanged. This halves the round trips to the database isolate during the 90-day
  scan.
- **A2. Payees streams are `autoDispose`** (`payee_providers.dart:20,25`). Today the GROUP BY
  query, plus one query per unnamed party, keeps re-running on every transactions write for the
  rest of the session after Payees is opened once. Riverpod's pause does not stop Drift's
  broadcast stream.
- **A3. Home reads the full history once per change, not twice.** Health index and the cash-flow
  forecast share one `homeLedgerProvider` and each slices its own window.
- **A4. Home and Insights watch `.select((s) => s.value)`**, which skips the extra frame each
  loading flag causes.
- **A5. The pill navigation bar drops `clipBehavior: Clip.antiAlias`**. The InkWell already has
  `customBorder: StadiumBorder()`, so it looks the same with one save layer fewer per frame.

Run configuration, with no repo change except the seed entry point in 0003:

- **B1. Emulator testing uses a profile build with Impeller off for the session:**
  `flutter run --profile --no-enable-impeller --flavor foss`. Profile is ahead-of-time compiled
  and debuggable (so screenshots and Maestro work, and FLAG_SECURE is off), and it installs over
  debug, keeping the data.
- **B2. Emulator for daily testing: `Pesa_AOSP_34`.** Android 14 with no Google services,
  x86_64, 4 vCPU, 3 GB, 720×1600 at 280 dpi, unused sensors off, SwiftShader. The `foss`
  flavour uses no Google services, and Google Play services caused 7 of the 10 ANRs. Keep the
  Google APIs image for `play`-flavour checks only.
- **B3. Automation must not poll the screen** while a person is testing. `uiautomator dump`
  starts an instrumentation process and turns on Flutter semantics, and `screencap` forces
  SurfaceFlinger readbacks. Both are expensive on SwiftShader.

## Alternatives considered

- **`EnableImpeller=false` in a manifest:** it would fix the emulator but silently change real
  devices, profiling and CI. Rejected; use the per-session CLI flag.
- **Host GPU for the emulator:** tried. Android 14 hung at boot and Android 36 forced software
  GLES. Rejected on this Mac.
- **Debounce ledger changes:** rejected (see Non-goals).

## Changes

- `lib/src/data/repositories/review_inbox_repository.dart`: `addAllIfNew`.
- `lib/src/data/repositories/transactions_repository.dart`: `addNew` uses `insertReturningOrNull`.
- `lib/src/features/sms/application/sms_ingestor.dart`: collect unmatched messages and make one
  `addAllIfNew` call.
- `lib/src/features/payees/application/payee_providers.dart`: `StreamProvider.autoDispose` ×2.
- `lib/src/features/home/application/home_ledger_provider.dart` (new); edits to
  `health_index_provider.dart` and `cash_flow_forecast_provider.dart`.
- `lib/src/features/home/presentation/home_screen.dart:63-66` and
  `lib/src/features/insights/presentation/insights_screen.dart:438`: `.select`.
- `lib/src/routing/app_shell.dart`: drop the clip (on top of the uncommitted pill bar).

## Acceptance criteria

- [ ] `flutter analyze --fatal-infos` is clean and `dart format` makes no changes.
- [ ] The whole `flutter test` suite passes, including `app_database_test.dart:546`,
      `sms_ingestor_test.dart`, `sms_scan_service_test.dart`, `export_and_details_test.dart`,
      `health_index_test.dart`, `cash_flow_forecast_test.dart`, `insights_test.dart` and
      `home_activity_test.dart`.
- [ ] After leaving Payees, a transactions write runs no payees GROUP BY query (checked with
      drift `logStatements` in a test).
- [ ] On `Pesa_AOSP_34` with the profile build, Impeller off and no automation running: 0
      `am_anr` over 15 idle minutes, and app RSS under 260 MB.

## Edge cases

- **Duplicate messages within a batch:** `DoNothing` on the unique index skips the second one,
  as the current check does.
- **A row with a NULL `dedupeKey`:** still inserted, since NULL never conflicts, as today.
- **Home before any accounts exist:** the forecast keeps its early return.
- **Payees reopened:** it shows the same first frame as a first visit.

## Test plan

Existing suites cover A1, A3 and A4. Add `test/data/payees_autodispose_test.dart` for A2. A5
is covered by `app_smoke_test.dart`. Manual check: the B1/B2 measurement above.

## Rollout & rollback

Ships with the next build, with no flag or migration. Each change is independent; revert the
commit for any one.

## Open questions

None blocking.
