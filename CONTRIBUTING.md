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
- Link the issue the change addresses. UI changes should include screenshots in light and dark mode.
- CI must pass before review.
