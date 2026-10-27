# Releasing

How a release of the app is built, signed and published. Nothing here has been submitted to a store yet; the checklists at the end track what is still to do.

## 1. Prepare

1. Bump `version` in `pubspec.yaml` (`name+code`, for example `0.2.0+2`). The code must go up on every release.
2. Add `fastlane/metadata/android/en-US/changelogs/<code>.txt`: a few plain sentences on what changed. F-Droid and the release notes read this file.
3. Make sure CI and the dependency scan are green on the release commit, then tag it `vX.Y.Z`.

## 2. Build settings

Release builds take these `--dart-define` values. Keep them in the release environment, not in the repo.

| Define | What it is |
| --- | --- |
| `PESACLARITY_API_URL` | The server's base URL (https only) |
| `PESACLARITY_CERT_PINS` | SPKI SHA-256 pins per host: `host=pin,pin;host=pin,pin`. At least two pins per host: the live key and a backup key kept offline. An invalid value makes the app refuse to connect, by design. |
| `PESACLARITY_PLAY_CLOUD_PROJECT` | `play` only: the Google Cloud project number for Play Integrity |

Get a pin from a server certificate or a backup key's certificate signing request:

```sh
openssl x509 -in server.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
openssl req -in backup.csr -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
```

Rotate keys by first shipping a release that pins both the current and the next key, then switching the server.

Build, with `SOURCE_DATE_EPOCH` set for reproducibility (see `docs/reproducible-builds.md`):

```sh
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
flutter build appbundle --release --flavor play --obfuscate --split-debug-info=build/symbols/play --dart-define=...
flutter build apk --release --flavor foss --obfuscate --split-debug-info=build/symbols/foss --dart-define=...
```

Keep `build/symbols` for each release (outside the repo) to read stack traces from crash reports.

## 3. Signing keys

The upload key (Play) and the release key (F-Droid and direct downloads) never go in the repo, in CI logs or on a shared drive.

- **Where the key lives.** In a hardware key (a YubiKey or similar PIV/PKCS#11 token, or a cloud HSM) or in a secrets manager with access logging. A backup copy is kept encrypted, offline, in a second location, with the recovery steps written down.
- **Who can use it.** Named release maintainers only. Using the key needs the hardware token or a manually approved secrets-manager request.
- **Local signing.** `android/key.properties` (see `android/key.properties.example`) points Gradle at the keystore. For a PKCS#11 token, sign the unsigned output with `apksigner sign --provider-class sun.security.pkcs11.SunPKCS11 --ks NONE --ks-type PKCS11 ...` instead.
- **CI signing (optional).** If CI signs, store the keystore and passwords as secrets in a protected GitHub environment that needs a maintainer's approval, decode the keystore to a temporary file in the job and delete it afterwards. Never sign pull-request builds.
- **Play App Signing.** Google holds the app signing key for Play; we hold the upload key. Register a new upload key with Play support if it is ever lost or exposed.
- **F-Droid.** With reproducible builds, F-Droid rebuilds the APK, checks it matches ours and ships it with our signature, so updates install over our direct-download APK.

## 4. Google Play: SMS permissions declaration

Play allows `READ_SMS` and `RECEIVE_SMS` only for approved core uses. Pesa Clarity applies under the SMS-based money management exception, and a person at Google reviews it. Before the first Play release (draft answers are in `docs/play-console.md`):

1. Check the app matches the policy: SMS budgeting is the core feature, no permissions beyond SMS, notifications, restart and network are requested, and the in-app disclosure before the SMS permission prompt explains what is read and why.
2. Publish the privacy policy at a public URL and add it to the store listing.
3. In Play Console, open **App content** and complete the permissions declaration form for SMS and Call Log permissions:
   - choose the core functionality that matches SMS-based money management;
   - describe how the app uses SMS: reads messages only from the banks and wallets the user selects, parses them on the phone and keeps only the transaction fields;
   - add a link to a short screen recording that shows the disclosure, the permission prompt and the feature that uses the messages.
4. Complete the **Data safety** form consistently with the privacy policy: SMS is processed on the phone and not collected by the server.
5. Upload the build to an internal or closed testing track and submit for review. Expect questions; answer from this page and the spec.

## 5. F-Droid

1. Reproducible build and the offenders in `docs/reproducible-builds.md` resolved for `foss`.
2. Store text and changelogs come from `fastlane/metadata/android/en-US`.
3. Open a merge request to fdroiddata with the build recipe: Flutter srclib at the pinned version, `foss` flavour, the same build command and defines, and our signing certificate for reproducible-build verification.

## Release checklist (not done yet)

- [ ] Server deployed; real certificate pins and a backup key generated and set in `PESACLARITY_CERT_PINS`
- [ ] Play Console project and Google Cloud project created; Play Integrity added to the `play` flavour behind `IntegrityAttestor`, with server-side token checks
- [ ] Upload and release keys created in a hardware key or secrets manager, with an offline backup
- [ ] SMS permissions declaration and Data safety form submitted and approved
- [ ] SQLCipher built from source for `foss`; PDFium handled before it ships in `foss`
- [ ] External penetration test against OWASP MASVS L2 passed, findings fixed
- [ ] Performance budget met on a 2 GB phone (`docs/performance-budget.md`)
- [ ] ODPC registration done (spec: Privacy and compliance)
