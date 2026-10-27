# Contributing to the Pesa Clarity app

Thank you for helping. The organisation-wide code of conduct, security policy and contributor terms live in [pesaclarity/.github](https://github.com/pesaclarity/.github); please read them first. Report security issues privately as described there, not in public issues.

## Set up

1. Install Flutter stable (3.47 or later). For device builds, install the Android SDK and JDK 17.
2. `flutter pub get`
3. `dart run build_runner build --delete-conflicting-outputs` (re-run after changing Drift tables)
4. `flutter run --flavor foss`

## Before you open a pull request

Run the same checks as CI:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

## UI flows

The [Maestro](https://maestro.mobile.dev) flows in `.maestro/` drive the app on a device and save screenshots. CI runs them in the `UI screenshots` workflow. To run them locally:

1. Install the Maestro CLI (CI pins the version in `.github/workflows/ui-screenshots.yml`) and start an Android emulator or connect a test phone with USB debugging on.
2. Build and install the app:

   ```sh
   flutter build apk --debug --flavor foss
   adb install -r build/app/outputs/flutter-apk/app-foss-debug.apk
   ```

3. Run every flow in light and dark mode: `./tool/run_ui_flows.sh`. Reports and screenshots land in `build/maestro/<theme>/`. To run one flow, use `maestro test -e THEME=light .maestro/tab-plan.yaml`. The onboarding flow runs first; if it fails, the rest of that theme is skipped and `./tool/ui_diagnostics.sh` saves logcat, a screenshot and the view hierarchy to `build/maestro/diagnostics/`.

Keep flow `name:` values free of `< > : " | ? * \`, because Maestro names output folders after them.

Select widgets with `id:` and add new identifiers to `lib/src/shared/semantic_ids.dart` and its widget test. Keep screenshot names stable; reviewers compare them across runs.

## Ground rules

- **Synthetic data only.** Never commit real SMS, statements, names or phone numbers. Use obviously fake values such as `0700 000 000`.
- **Money is integer minor units.** Use `Money`; never store or calculate amounts as `double`.
- **Nothing leaves the phone** unless the spec says so. New network calls, permissions or SDKs need an issue and agreement first.
- **The `foss` flavour stays free of Google services.** Anything that needs them must be gated on `AppFlavor.allowsGoogleServices` and kept out of the `foss` build.
- **Database changes** bump `schemaVersion` and add a migration.
- Keep comments for the non-obvious *why*; keep public APIs documented.

## Commits and pull requests

- Small, focused pull requests against `main`, with a short description of what changed and why.
- Clear, one-line commit messages in the imperative ("Add payee table").
- Link the issue the change addresses. UI changes should include screenshots in light and dark mode; run the `UI screenshots` workflow on your branch from the Actions tab and its artifact has both.
- CI must pass before review.
