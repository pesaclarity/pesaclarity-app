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
| `play` | Google Play | May use Google services (Sign-In, Play Integrity) |
| `foss` | F-Droid | No Google services or other proprietary dependencies |

Dart code reads the flavour through `appFlavorProvider` (`lib/src/config/flavor.dart`). Builds without a known flavour, including tests, behave as `foss`.

### Server

Accounts (sign-in, devices, delete account) talk to the Pesa Clarity server. People sign in with a 6-digit code sent to their email. `play` builds also offer Google sign-in through Android's Credential Manager when built with `--dart-define=PESACLARITY_GOOGLE_SERVER_CLIENT_ID=<web client id>` (the same id the server lists in `NGOME_GOOGLE_CLIENT_IDS`). Its Kotlin lives in `android/app/src/play/` and its libraries are `playImplementation` dependencies, so `foss` builds carry no Google code and sign in by email only. Set the server address at build time:

```sh
flutter run --flavor foss --dart-define=PESACLARITY_API_URL=https://api.example.org
```

Only `https` is accepted, apart from `http://10.0.2.2`, `localhost` and `127.0.0.1` for local development. Without it, the app works fully without an account and sign-in explains that accounts come in a later update.

## Project layout

```text
lib/
  main.dart
  src/
    app.dart                 root widget
    config/                  build flavour
    core/backup/             .pcbackup format: AES-256-GCM, Argon2id, recovery key (pure Dart)
    core/network/            pinned HttpClient factory (trusted roots per host, from build config)
    core/integrity/          IntegrityAttestor: Play stub, foss no-op, request header hook
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
.maestro/                    Maestro UI flows (YAML), one per journey
tool/run_ui_flows.sh         runs the flows in light and dark mode
android/                     Android project (applicationId com.pesaclarity.app)
assets/fonts/                Space Grotesk and Inter, with their OFL licences
```

State is managed with Riverpod and navigation with go_router.

## Security baseline

From the spec's "Mobile security" section:

- Database encrypted with SQLCipher. The 256-bit key is generated on the phone and kept in Android Keystore-backed secure storage. The app refuses to open the database if SQLCipher is not loaded.
- `FLAG_SECURE` on the main activity blocks screenshots, recording and app-switcher previews in release builds. Debuggable builds skip it so CI can capture UI screenshots; release builds are never debuggable.
- Android auto-backup and device transfer are off (`allowBackup="false"` plus extraction rules that exclude everything).
- Permissions: `READ_SMS`, `RECEIVE_SMS`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED` (to restore reminders after a restart) and `INTERNET` (sign-in, backups and the privacy policy) only. `test/android/manifest_permissions_test.dart` fails if the list changes. Cleartext traffic is off.
- Cleartext traffic is refused. Every `HttpClient` comes from `HttpClientFactory` (`lib/src/core/network`). Our servers are pinned to their certificate authorities, not their keys, because the hosting providers renew certificates with new keys every few months: connections to the hosts in `PESACLARITY_PINNED_HOSTS` trust only the roots in `PESACLARITY_TRUSTED_ROOTS` (two or more), and a misconfiguration refuses every connection. Third-party services (Google Drive) use the platform's authorities. A test fails if code creates an `HttpClient` any other way. The real values are set once the server is deployed.
- Device integrity: `IntegrityAttestor` (`lib/src/core/integrity`) supplies a token header for backup and federated-learning requests; the `play` stub returns "unavailable" until the Play project exists, and `foss` never attests. A light root and tamper check (`DeviceIntegrityChannel.kt`) shows a one-time notice in Profile and never blocks use.
- Dependencies are scanned with OSV-Scanner in CI (`.github/workflows/dependency-scan.yml`) and updated by Dependabot.
- R8 minification and resource shrinking on release builds; Dart obfuscation via `--obfuscate`.

Not done yet: unlock with BiometricPrompt or PIN before the key is released, StrongBox, the pinned hosts and roots for the deployed server, and Play Integrity tokens. These are marked `TODO(security)` and similar in the code.

Releases: see [RELEASING.md](RELEASING.md), [docs/reproducible-builds.md](docs/reproducible-builds.md) and [docs/performance-budget.md](docs/performance-budget.md). F-Droid store text lives in `fastlane/metadata/android/en-US`.

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
- **Parsing** runs on a background isolate. A parsed message keeps its fields (amount, time, fee, receipt, balance, counterparty) and a SHA-256 hash; the text is discarded. Each institution gets its own account, created on its first transaction. Transactions are deduplicated per account by ujumbe's dedupe key (receipt, amount and minute), which statement imports share. Counterparties are normalised with `PayeeIdentifier`, so named payees apply.
- **Notifications.** For phones without SMS access, Profile › Read from notifications reads the notifications the messages app shows. `NotificationCaptureService.kt` (a `NotificationListenerService` the person allows in the phone's settings) keeps only those whose sender is a watched sender ID, encrypted with an Android Keystore key in a no-backup file, until the app drains them. Notification text can be cut short, so a message no rule reads is dropped instead of going to review. Each message is counted once with SMS, by the same dedupe key.
- **Review inbox.** A message from a selected sender that no rule matches is kept for review, text included, because tagging its fields to make a local rule needs the text. It lives only in the SQLCipher database and its text is deleted when the item is resolved; the hash stays so a later scan does not bring it back.

## Statement import

- **On the phone only.** The PDF and its password never leave the phone. The password goes straight to PDFium and is cleared once used.
- **Positioned words.** `PdfiumTextExtractor` returns each page's words with their boxes (`page_words.dart` builds words from PDFium's character boxes). ujumbe's statement packs pick the layout and rebuild the table from those positions, so columns and wrapped details survive; see the [statement import spec](https://github.com/pesaclarity/docs/blob/main/spec/statement-import.md).
- **Off the UI isolate.** PDFium runs on pdfrx's worker; layout and parsing run in `Isolate.run`.
- **Importing.** Rows match SMS by ujumbe's dedupe key, new ones are added, and the result is reconciled to the closing balance. A recognised bank with no statement pack yet shows "coming soon".
- **Fixtures.** `test/fixtures/synthetic_statement*.pdf` are synthetic M-Pesa statements (one AES-encrypted, password `0000`) made by `tool/fixtures/statement_pdfs.py`. Never commit a real statement.
- **F-Droid.** The `foss` build has no PDFium and hides statement import (`tool/prepare_foss.sh`).

## On-device categoriser

- **Features.** `lib/src/domain/categoriser/features.dart` is a Dart port of `akili.features` in [pesaclarity/pesaclarity-ml](https://github.com/pesaclarity/pesaclarity-ml) (feature schema version 1). `test/fixtures/categoriser/feature_vectors.v1.json` is a copy of that repo's conformance vectors, and the tests check every case. When the ML repo bumps the schema, copy the new vectors and port the change.
- **Model.** No model ships with the app; one arrives only after passing the ML repo's privacy release gate. An installed model sits in the app's support directory under `categoriser/`, with `model-manifest.json` and `labels.json`. The app refuses it, and uses the rules below instead, when the feature schema, config or input differ from what it produces, or when the file's size or SHA-256 differ from the manifest.
- **Runtime.** `tflite_flutter` (Apache-2.0, published by tensorflow.org) runs the model, and only `tflite_flutter_runtime.dart` imports it. On Android it links Google's prebuilt LiteRT AAR from Maven, so F-Droid may require LiteRT built from source or another runtime behind the `TfliteRuntime` interface.
- **Without a model** suggestions come from the message type (airtime, Fuliza, charges) and well-known payee names.
- **Your choices win.** Accepting or changing a suggestion sets that transaction's category and remembers it for the payee; the next transaction from that payee suggests the same category first. Each choice is also logged on the phone as encoded features and a label, never the payee text, for later fine-tuning.
- **Learning** (on-device fine-tuning and federated updates) runs only when "Help improve the app" is on. The gate and interfaces are in `learning.dart`; the trainers are not built yet.

## Testing

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

Tests cover the domain rules with synthetic ledgers, money formatting, the theme against the brand tokens, the flavour rules, the database (including a check that the bundled SQLite really is SQLCipher), the My accounts selection and saved onboarding state, SMS capture against a fake inbox (mapping, dedupe, sender filtering, review inbox, scans), the onboarding redirect, and widget tests through onboarding, My accounts and the five tabs. Test data is synthetic only; never commit real SMS, statements or phone numbers.

CI runs the same checks on every pull request and builds a `foss` APK.

## UI screenshots

The `UI screenshots` workflow (`.github/workflows/ui-screenshots.yml`) builds a `foss` debug APK, starts an Android 14 emulator (Pixel 6 profile) and runs the [Maestro](https://maestro.mobile.dev) flows in `.maestro/` twice, in light and dark mode. Each flow walks one journey (onboarding with the account picker before and after ticking M-Pesa, the five tabs, Profile, Profile > My accounts, Debts, Backup, Privacy), checks the screen title is visible and saves a screenshot with a stable name such as `01-onboarding-welcome-dark.png`. Screenshots and JUnit reports are uploaded as the `ui-screenshots` artifact, and the job summary lists the captured names.

It runs on demand (Actions tab, any branch) and on pull requests that change the flows or the workflow. Flows select widgets by Semantics identifiers listed in `lib/src/shared/semantic_ids.dart`; `test/widget/semantic_ids_test.dart` fails if one goes missing.

The screenshot workflow uses the debug APK, which skips `FLAG_SECURE`; release builds keep it.

## Branches and releases

`main` is what users get; nothing lands there untested.

1. Pull requests go to `dev`, with a [Conventional Commits](https://www.conventionalcommits.org) title (`feat: …`, `fix: …`, `feat!: …` for a breaking change; `docs`, `test`, `ci`, `chore`, `refactor`, `build`, `perf`, `style`, `revert` too). The `PR title` check enforces it, and squash merges keep the title as the commit message.
2. Each push to `dev` runs CI and the `Test APK` workflow, which builds `play` and `foss` release APKs against the `DEV_PESACLARITY_*` variables and keeps them as artifacts for 30 days.
3. When `dev` is ready, open a pull request from `dev` to `main`. The `Release gate` check allows only `dev` (or the release pull request) into `main`, and its QA job waits for a reviewer in the `qa` environment to approve after trying the test APK. Merge it with a merge commit, not a squash, so each change keeps its own title.
4. On `main`, release-please keeps a release pull request open with the next version (SemVer from the titles: `feat` bumps the minor, `fix` the patch; before 1.0 a breaking change bumps the minor) and the `CHANGELOG.md` entry. Merging it tags `vX.Y.Z`, uploads to Google Play (below) and merges the release back into `dev`.

## Releasing to Google Play

The `Release to Google Play` workflow (`.github/workflows/release-play.yml`) runs the tests, builds a signed `play` App Bundle and uploads it to Google Play. It runs when release-please tags a release, by hand from the Actions tab with a track and status, or on a tag such as `v0.1.0` pushed by hand. Releases and tags go to the track and status set in `PLAY_TAG_TRACK` and `PLAY_TAG_STATUS`. Each upload gets version code `run number + PLAY_VERSION_CODE_OFFSET`, leaving room for builds uploaded by hand; the version name comes from `pubspec.yaml`. The bundle, R8 mapping and Dart symbols are kept as the `pesaclarity-play-release` artifact.

One-time setup:

1. Create the app in Play Console with package name `com.pesaclarity.app`, fill in the store listing, content rating and data safety form, and turn on Play App Signing.
2. Make an upload key and keep it, and its passwords, somewhere safe. Losing it means asking Google to reset it.

   ```sh
   keytool -genkeypair -keystore upload.jks -alias upload -keyalg RSA -keysize 4096 -validity 10000
   ```

3. In Google Cloud, create a service account, download a JSON key, and invite its email in Play Console under Users and permissions with release rights for this app.
4. Add these as repository secrets: `PLAY_UPLOAD_KEYSTORE_BASE64` (`base64 -w0 upload.jks`), `PLAY_UPLOAD_KEYSTORE_PASSWORD`, `PLAY_UPLOAD_KEY_ALIAS`, `PLAY_UPLOAD_KEY_PASSWORD` and `PLAY_SERVICE_ACCOUNT_JSON` (the whole JSON file).
5. Add repository variables: `PLAY_PACKAGE_NAME` (the application id, `com.pesaclarity.app` today), `PLAY_VERSION_CODE_OFFSET` (higher than any version code uploaded by hand), and for tag releases `PLAY_TAG_TRACK` (`internal`, `alpha`, `beta` or `production`) and `PLAY_TAG_STATUS` (`draft` or `completed`). The workflow stops with a list of any that are missing.
6. Optionally add repository variables for the build: `PESACLARITY_API_URL` and `PESACLARITY_VAULT_URL` (the server's https address), `PESACLARITY_GOOGLE_SERVER_CLIENT_ID`, `PESACLARITY_PLAY_CLOUD_PROJECT`, `PESACLARITY_PINNED_HOSTS` and `PESACLARITY_TRUSTED_ROOTS`.

For an app that has never been released, Google only accepts draft uploads: run the workflow once with status `draft`, then roll the release out from Play Console. New personal developer accounts must also run a closed test with at least 12 testers for 14 days before they can publish to production.

Pull requests that change the workflow or `android/` build the bundle with a throwaway key and skip the upload.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

The app is licensed under the [GNU Affero General Public License v3.0](LICENSE). A commercial licence is available on request for organisations that cannot accept the AGPL.

The bundled fonts are under the SIL Open Font License 1.1. The Pesa Clarity name and logo are trademarks of the project and are not covered by the AGPL; forks must use a different name and logo.
