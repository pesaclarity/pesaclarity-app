# Pesa Clarity app (mfuko)

Pesa Clarity is a free, ad-free, open-source Android app that turns M-Pesa and bank SMS into a clear daily plan: what you can safely spend today, which bills are due, where money leaks, and when you will be debt-free. All analysis runs on the phone. This repository holds the Flutter app.

**Codename:** *mfuko*, Swahili for "pocket".

**Status:** pre-alpha. The structure, theme, encrypted database and navigation are in place; the screens are placeholders that state what each one will show, apart from safe to spend on Home.

The product spec, brand guide and design tokens live in [pesaclarity/docs](https://github.com/pesaclarity/docs).

## Quick start

You need Flutter stable (3.47 or later) and, for device builds, the Android SDK with JDK 17.

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift code generation
flutter run --flavor foss                                  # or --flavor play
```

Build a release APK:

```sh
flutter build apk --release --flavor foss --obfuscate --split-debug-info=build/symbols
```

Release builds use the debug key unless `android/key.properties` exists (see `android/key.properties.example`). Keystores never go in the repo.

iOS comes after the Android MVP. Add the platform then with `flutter create --platforms ios .`.

## Build flavours

| Flavour | For | Rule |
| --- | --- | --- |
| `play` | Google Play | May use Google services (Sign-In, Play Integrity) once they are added |
| `foss` | F-Droid | No Google services or other proprietary dependencies |

Dart code reads the flavour through `appFlavorProvider` (`lib/src/config/flavor.dart`). Builds without a known flavour, including tests, behave as `foss`.

## Project layout

```text
lib/
  main.dart
  src/
    app.dart                 root widget
    config/                  build flavour
    core/money/              Money (integer minor units) and KES formatting
    domain/                  pure-Dart money rules, no Flutter or database imports
      time/                  Nairobi calendar dates and months
      ledger/                own transfers, Fuliza fees, noise collapse, honest totals
      budget/                safe to spend today, weekday and weekend limits
    data/
      database/              Drift tables, SQLCipher connection, key store
      repositories/          thin repository interfaces and Drift implementations
    features/                one folder per screen in the spec
      onboarding/ home/ activity/ plan/ goals/ debts/
      insights/ profile/ backup/ privacy/
    routing/                 go_router: five-tab shell; Profile under Home, Debts under Goals
    shared/widgets/
    theme/                   brand tokens, light and dark themes, typography
test/                        unit, widget and database tests
android/                     Android project (applicationId com.pesaclarity.app)
assets/fonts/                Space Grotesk and Inter, with their OFL licences
```

State is managed with Riverpod and navigation with go_router.

## Security baseline

From the spec's "Mobile security" section:

- Database encrypted with SQLCipher. The 256-bit key is generated on the phone and kept in Android Keystore-backed secure storage. The app refuses to open the database if SQLCipher is not loaded.
- `FLAG_SECURE` on the main activity blocks screenshots, recording and app-switcher previews.
- Android auto-backup and device transfer are off (`allowBackup="false"` plus extraction rules that exclude everything).
- Permissions: `READ_SMS`, `RECEIVE_SMS` and `POST_NOTIFICATIONS` only. `INTERNET` is present only in debug and profile builds for Flutter tooling; release builds get it when sign-in and the backup vault land.
- Cleartext traffic is refused and only system certificate authorities are trusted. Certificate pinning comes with the server endpoints.
- R8 minification and resource shrinking on release builds; Dart obfuscation via `--obfuscate`.

Not done yet: unlock with BiometricPrompt or PIN before the key is released, StrongBox, certificate pinning and Play Integrity. These are marked `TODO(security)` and similar in the code.

## SQLCipher

The database uses `package:sqlite3` 3.x with its SQLCipher build, chosen in `pubspec.yaml` under `hooks.user_defines.sqlite3.source`. This replaces `sqlcipher_flutter_libs`, which reached end of life when `sqlite3` 3.x began bundling SQLCipher itself. The build hook downloads checksum-verified SQLCipher binaries from the `sqlite3.dart` GitHub releases; F-Droid may require building SQLCipher from source instead (the hook supports `source: source`).

## Fonts

Space Grotesk (numbers and titles, tabular figures) and Inter (body text) are bundled in `assets/fonts/` as variable fonts. The app never fetches fonts over the network. Both are under the SIL Open Font License 1.1; the licence texts sit next to the font files. To update them, take `ofl/spacegrotesk/SpaceGrotesk[wght].ttf` and `ofl/inter/Inter[opsz,wght].ttf` from [google/fonts](https://github.com/google/fonts).

## Parser package

SMS parsing comes from the `ujumbe` Dart package in [pesaclarity/ujumbe-parsers](https://github.com/pesaclarity/ujumbe-parsers). It is being built alongside this app and has no `pubspec.yaml` on `main` yet, so the git dependency is commented out in `pubspec.yaml` with a `TODO(ujumbe)`. Uncomment it once the package is published there.

## Testing

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

Tests cover the domain rules with synthetic ledgers, money formatting, the theme against the brand tokens, the flavour rules, the database (including a check that the bundled SQLite really is SQLCipher), and a widget smoke test through onboarding and the five tabs. Test data is synthetic only; never commit real SMS, statements or phone numbers.

CI runs the same checks on every pull request and builds a `foss` APK.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

The app is licensed under the [GNU Affero General Public License v3.0](LICENSE). A commercial licence is available on request for organisations that cannot accept the AGPL.

The bundled fonts are under the SIL Open Font License 1.1. The Pesa Clarity name and logo are trademarks of the project and are not covered by the AGPL; forks must use a different name and logo.
