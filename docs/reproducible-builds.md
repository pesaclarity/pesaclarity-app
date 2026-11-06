# Reproducible builds

The spec asks that anyone can confirm a published APK matches this source. F-Droid can then ship our signed APK after rebuilding it and comparing. This page lists what that needs and what currently stands in the way.

## What a reproducible build needs

| Need | Status on `main` |
| --- | --- |
| Pinned Flutter SDK | CI pins `FLUTTER_VERSION: "3.47.8"`; `pubspec.yaml` only asks for `>=3.47.0`. Release builds must use the CI version exactly, and the F-Droid recipe must name the same Flutter tag as its srclib. |
| Locked Dart dependencies | `pubspec.lock` is committed. The one git dependency (`ujumbe`) is pinned to a commit; switch it to a tag once one exists. |
| Pinned Android toolchain | AGP 9.4.1, Kotlin 2.4.21 and Gradle 9.8.2 are pinned in `android/settings.gradle.kts` and `gradle-wrapper.properties`. JDK 17 (Temurin in CI). The compile and target SDK come from the Flutter version, so pinning Flutter pins them. |
| Same build path | Flutter compiles the absolute path of a generated file (`.dart_tool/flutter_build/dart_plugin_registrant.dart`) into `libapp.so`, and native libraries built by package hooks, such as `libdartjni.so`, carry a build id that depends on it. Builds in two folders differ in both, so build a `foss` release in `/home/vagrant/build/com.pesaclarity.app`, the path F-Droid's builder uses. |
| No build timestamps | Set `SOURCE_DATE_EPOCH` to the release commit time: `export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)`. Avoid `DateTime.now()` or `BuildConfig` timestamps in build scripts. |
| No dependency metadata blob | Done: `dependenciesInfo { includeInApk = false; includeInBundle = false }` in `android/app/build.gradle.kts`. |
| Same build command | `flutter build apk --release --flavor foss --obfuscate --split-debug-info=build/symbols`, plus the same `--dart-define` values (see `RELEASING.md`). Different defines produce a different APK. |
| No prebuilt binaries in `foss` | Run `tool/prepare_foss.sh` first. PDFium and SQLCipher are done; LiteRT is open (see below). |
| No committed binaries | Done: no `.jar`, `.so` or `.aar` files are in the repo. The Gradle wrapper jar is not committed; Flutter supplies it. |

## Current offenders

1. **SQLCipher.** Resolved: `pubspec.yaml`'s `hooks.user_defines.sqlite3.source: sqlcipher` makes `package:sqlite3`'s build hook download a prebuilt `libsqlcipher.so`, so `tool/prepare_foss.sh` runs `tool/foss/sqlcipher.sh` instead. That fetches SQLCipher 4.19.0 (the prebuilt's version) and LibTomCrypt 1.18.2 at pinned commits, makes SQLCipher's single-file source with SQLCipher's own build, and points the hook at it (`source: source`), so the hook compiles `libsqlite3.so` for each chip with the prebuilt's compile options. LibTomCrypt supplies the crypto, since the hook can't build OpenSSL for each chip. Databases are the SQLCipher 4 format either way, and `test/data/sqlcipher_format_test.dart` reads one made by each build. The `Foss build` workflow fails if the APK holds the prebuilt or a library without LibTomCrypt, and the UI flows run on this build. F-Droid's recipe can pass its own checkouts as `SQLCIPHER_SRC` and `LIBTOMCRYPT_SRC`.
2. **PDFium.** Resolved: `tool/prepare_foss.sh` removes `pdfrx_engine` and `pdfium_flutter` and swaps in `tool/foss/pdf_engine.dart`, so the `foss` build has no PDF engine and hides statement import. The `Foss build` workflow runs the script and fails if `libpdfium` is in the APK.
3. **Flutter engine.** The Flutter SDK downloads its engine artefacts. F-Droid builds Flutter apps with the SDK as a srclib; follow fdroiddata's current guidance for Flutter when writing the recipe.
4. **LiteRT.** `tflite_flutter` links Google's prebuilt LiteRT AAR from Maven Central, with native libraries in it. F-Droid accepts some libraries from Maven Central; if its reviewers don't accept this one, LiteRT needs building from source in the recipe, or another runtime behind `TfliteRuntime`.

## Checking a build

The **Reproducible build** workflow does this on every change to `main` that touches the app, and on pull requests that change the Android build, the dependencies or the foss preparation. It builds the foss APKs twice, each time from a fresh copy of the checkout in F-Droid's build path, with the release flags and one throwaway key, and fails if the files differ. `tool/compare_apks.py` then names the entries that differ, and the run keeps both APKs for diffoscope.

It doesn't vary the Flutter SDK's location, the user or the machine, as F-Droid's builder will. Before the first F-Droid submission, also check by hand:

1. Build the release twice from a clean checkout of the same tag, in two fresh containers, with the same Flutter version, JDK and `SOURCE_DATE_EPOCH`.
2. Compare the unsigned APKs with `diffoscope`. Expect only the signature to differ.
3. To compare against a signed APK, copy the signature across with `apksigcopier compare signed.apk --unsigned unsigned.apk`. A match means the signed APK was built from this source.
4. Record any difference as an issue with the `reproducible-builds` label and the diffoscope output.
