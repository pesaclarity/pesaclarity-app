# Contributing to the Pesa Clarity app

Thank you for helping. The organisation-wide code of conduct, security policy and contributor terms live in [pesaclarity/.github](https://github.com/pesaclarity/.github); please read them first. Report security issues privately as described there, not in public issues.

## Set up

1. Install Flutter stable (3.47 or later). For device builds, install the Android SDK and JDK 17.
2. `flutter pub get`
3. `dart run build_runner build --delete-conflicting-outputs` (re-run after changing Drift tables)
4. `flutter run --flavor foss`

## Checks run on your machine

GitHub only builds and releases; the checks run locally. Once per clone, run:

```sh
tool/setup-hooks
```

Then every `git push` first checks that each commit being pushed has a [Conventional Commits](https://www.conventionalcommits.org) title, and runs `tool/check`: formatting, `flutter analyze --fatal-infos --fatal-warnings`, the whole test suite (a few minutes), an [OSV-Scanner](https://google.github.io/osv-scanner/) dependency scan, and the UI flows when your branch changes them. A step whose tool is not installed is skipped with a notice saying how to install it.

- `tool/check --fast`: formatting, analysis and the quick tests, in under a minute. Handy while you work.
- `tool/check --deps`: only the dependency scan. Run it now and then; new advisories appear without any change here.
- `tool/check --ui`: only the UI flows (below).

Versions, test folders and the title rule are in `tool/check.env`. In an emergency, `git push --no-verify` skips the hook; run `tool/check` soon after.

## UI flows

The [Maestro](https://maestro.mobile.dev) flows in `.maestro/` drive the app on a device and save screenshots. `tool/check` runs them when your branch changes them, and `tool/check --ui` runs them any time; it builds and installs the app itself. To run them by hand:

1. Install the Maestro CLI (the version is in `tool/check.env`) and start an Android emulator or connect a test phone with USB debugging on.
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

- Small, focused pull requests against `dev`, with a short description of what changed and why. `main` takes only `dev` and release pull requests (see [Branches and releases](README.md#branches-and-releases)).
- Pull request titles follow [Conventional Commits](https://www.conventionalcommits.org): `feat: add payee table`, `fix: …`, `feat!: …` for a breaking change. They set the next version and the changelog.
- Commit titles follow the same rule (the pre-push hook checks them): `feat: add payee table`.
- Link the issue the change addresses. UI changes should include screenshots in light and dark mode; `tool/check --ui` saves both in `build/maestro/`.
- `tool/check` must pass before review; the pre-push hook runs it.
