# Reproducible builds

The spec asks that anyone can confirm a published APK matches this source. F-Droid can then ship our signed APK after rebuilding it and comparing. This page lists what that needs and what currently stands in the way.

## What a reproducible build needs

| Need | Status on `main` |
| --- | --- |
| Pinned Flutter SDK | CI pins `FLUTTER_VERSION: "3.47.8"`; `pubspec.yaml` only asks for `>=3.47.0`. Release builds must use the CI version exactly, and the F-Droid recipe must name the same Flutter tag as its srclib. |
| Locked Dart dependencies | `pubspec.lock` is committed. The one git dependency (`ujumbe`) is pinned to a commit; switch it to a tag once one exists. |
| Pinned Android toolchain | AGP 9.4.1, Kotlin 2.4.21 and Gradle 9.8.2 are pinned in `android/settings.gradle.kts` and `gradle-wrapper.properties`. JDK 17 (Temurin in CI). The compile and target SDK come from the Flutter version, so pinning Flutter pins them. |
| No build timestamps | Set `SOURCE_DATE_EPOCH` to the release commit time: `export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)`. Avoid `DateTime.now()` or `BuildConfig` timestamps in build scripts. |
| No dependency metadata blob | Done: `dependenciesInfo { includeInApk = false; includeInBundle = false }` in `android/app/build.gradle.kts`. |
| Same build command | `flutter build apk --release --flavor foss --obfuscate --split-debug-info=build/symbols`, plus the same `--dart-define` values (see `RELEASING.md`). Different defines produce a different APK. |
| No prebuilt binaries in `foss` | Run `tool/prepare_foss.sh` first. PDFium is done; SQLCipher is not yet (see below). |
| No committed binaries | Done: no `.jar`, `.so` or `.aar` files are in the repo. The Gradle wrapper jar is not committed; Flutter supplies it. |

## Current offenders

1. **SQLCipher (`package:sqlite3` build hook).** `hooks.user_defines.sqlite3.source: sqlcipher` in `pubspec.yaml` makes the hook download a prebuilt `libsqlcipher.so` from the `sqlite3` package's GitHub releases (checked against hashes in the package). F-Droid does not accept prebuilt native libraries. Fix for `foss`: compile SQLCipher from source with the hook's `source: source` option (pointing `path` at a SQLCipher amalgamation built in the F-Droid recipe, with its crypto library), or have the recipe build the library and use `source: system`. This needs testing on a device before the first F-Droid submission.
2. **PDFium.** Resolved: `tool/prepare_foss.sh` removes `pdfrx_engine` and `pdfium_flutter` and swaps in `tool/foss/pdf_engine.dart`, so the `foss` build has no PDF engine and hides statement import. The `Foss build` workflow runs the script and fails if `libpdfium` is in the APK.
3. **Flutter engine.** The Flutter SDK downloads its engine artefacts. F-Droid builds Flutter apps with the SDK as a srclib; follow fdroiddata's current guidance for Flutter when writing the recipe.

## Checking a build

1. Build the release twice from a clean checkout of the same tag, in two fresh containers, with the same Flutter version, JDK and `SOURCE_DATE_EPOCH`.
2. Compare the unsigned APKs with `diffoscope`. Expect only the signature to differ.
3. To compare against a signed APK, copy the signature across with `apksigcopier compare signed.apk --unsigned unsigned.apk`. A match means the signed APK was built from this source.
4. Record any difference as an issue with the `reproducible-builds` label and the diffoscope output.
