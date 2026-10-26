# Pesa Clarity app

Pesa Clarity is a free, ad-free, open-source Android app that turns M-Pesa and bank SMS into a clear daily plan: what you can safely spend today, which bills are due, where money leaks, and when you will be debt-free. All analysis runs on the phone. This repository holds the Flutter app.

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
    core/backup/             .pcbackup format: AES-256-GCM, Argon2id, recovery key (pure Dart)
    core/money/              Money (integer minor units) and KES formatting
    domain/                  pure-Dart money rules, no Flutter or database imports
      time/                  Nairobi calendar dates and months
      ledger/                own transfers, Fuliza fees, noise collapse, honest totals
      budget/                safe to spend today, weekday and weekend limits
      plan/                  monthly plan, arrears, category status, surplus split, snapshots
      payees/                identifier normalising and matching, payee and override precedence
      categories/            default Kenyan category set (keys shared with the categoriser)
      tags/                  tag names, filtering and totals by tag
      debts/                 payoff strategies, payday split, family loans, Fuliza tracker, repayment matching
      health/                Financial Health Index: eight indicators, bands, best action
      forecast/              cash-flow forecast to month end: zero date, charges that may fail
    data/
      database/              Drift tables, SQLCipher connection, key store
      repositories/          thin repository interfaces and Drift implementations
    features/                one folder per screen in the spec
      onboarding/ home/ activity/ plan/ goals/ debts/
      insights/ profile/ backup/ privacy/ accounts/
      sms/                   SMS permission, inbox scan, live capture, parsing
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

SMS parsing comes from the `ujumbe` Dart package in [pesaclarity/ujumbe-parsers](https://github.com/pesaclarity/ujumbe-parsers), a git dependency pinned to a commit on `main` until `v0.1.0` is tagged. The institutions in My accounts are its bundled parser packs: each pack gives the id, name and sender IDs.

## SMS capture

- **Only selected senders.** The Android side (`SmsChannel.kt`) queries the inbox and listens for `SMS_RECEIVED` with the sender IDs of the ticked institutions; every other message is filtered out before it reaches Dart. The Dart parser filters by sender again.
- **Permission.** `READ_SMS` and `RECEIVE_SMS` are asked for only after a screen that says in plain words what is read, kept and discarded. Refusing is fine: onboarding goes on without messages.
- **Scans.** "Scan my messages" reads the last 90 days. Afterwards, each time the app opens it reads what arrived since the last scan (90 days for a newly ticked institution), then adds new messages as they land while it runs. Messages that arrive while the app is closed wait in the inbox for the next scan, so there is no background service.
- **Parsing** runs on a background isolate. A parsed message keeps its fields (amount, time, fee, receipt, balance, counterparty) and a SHA-256 hash; the text is discarded. Each institution gets its own account, created on its first transaction. Transactions are deduplicated per account by ujumbe's dedupe key (receipt, amount and minute), which statement imports will share. Counterparties are normalised with `PayeeIdentifier`, so named payees apply.
- **Review inbox.** A message from a selected sender that no rule matches is kept for review, text included, because tagging its fields to make a local rule needs the text. It lives only in the SQLCipher database and its text is deleted when the item is resolved; the hash stays so a later scan does not bring it back.

## Testing

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

Tests cover the domain rules with synthetic ledgers, money formatting, the theme against the brand tokens, the flavour rules, the database (including a check that the bundled SQLite really is SQLCipher), the My accounts selection and saved onboarding state, SMS capture against a fake inbox (mapping, dedupe, sender filtering, review inbox, scans), the onboarding redirect, and widget tests through onboarding, My accounts and the five tabs. Test data is synthetic only; never commit real SMS, statements or phone numbers.

CI runs the same checks on every pull request and builds a `foss` APK.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

The app is licensed under the [GNU Affero General Public License v3.0](LICENSE). A commercial licence is available on request for organisations that cannot accept the AGPL.

The bundled fonts are under the SIL Open Font License 1.1. The Pesa Clarity name and logo are trademarks of the project and are not covered by the AGPL; forks must use a different name and logo.
