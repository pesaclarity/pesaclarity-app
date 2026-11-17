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
| No prebuilt binaries in `foss` | Run `tool/prepare_foss.sh` first. It removes PDFium and compiles SQLCipher from source (see below). |
| No committed binaries | Done: no `.jar`, `.so` or `.aar` files are in the repo. The Gradle wrapper jar is not committed; Flutter supplies it. |

## Current offenders

1. **SQLCipher (`package:sqlite3` build hook).** Resolved for `foss`. In `play`, `hooks.user_defines.sqlite3.source: sqlcipher` makes the hook download a prebuilt `libsqlcipher.so` from the `sqlite3` package's GitHub releases (checked against hashes in the package); it links OpenSSL. For `foss`, `tool/prepare_foss.sh` runs `tool/foss/build_sqlcipher_sources.sh`, which takes SQLCipher 4.20.0 (the version in the prebuilt) and LibTomCrypt 1.18.2 at pinned commits, generates SQLCipher's `sqlite3.c` with its own build (`./configure --disable-tcl`, so only a host C compiler and `make`), checks the SHA-256 of `sqlite3.c` and of the LibTomCrypt files it copies, and writes them to `tool/foss/sqlcipher/` (git-ignored). It then switches the hook to `source: source` with those files and the prebuilt's compile options, with LibTomCrypt as the crypto provider in place of OpenSSL. The hook compiles them with the NDK during `flutter build`; nothing is downloaded then. Databases are the same format either way (SQLCipher 4 defaults: AES-256-CBC, HMAC-SHA512, PBKDF2-HMAC-SHA512, 4096-byte pages), so a backup made by one build restores in the other; `test/data/sqlcipher_format_test.dart` opens a database made by each. Still to do: open a `play` database with a `foss` build on a device before the first F-Droid submission.
2. **PDFium.** Resolved: `tool/prepare_foss.sh` removes `pdfrx_engine` and `pdfium_flutter` and swaps in `tool/foss/pdf_engine.dart`, so the `foss` build has no PDF engine and hides statement import. The `Foss build` workflow runs the script and fails if `libpdfium` is in the APK.
3. **Flutter engine.** The Flutter SDK downloads its engine artefacts. F-Droid builds Flutter apps with the SDK as a srclib; follow fdroiddata's current guidance for Flutter when writing the recipe.

## F-Droid recipe

The recipe's `prebuild` runs `tool/prepare_foss.sh`. For SQLCipher it needs:

- `git`, a C compiler and `make` on the build server (for SQLCipher's `./configure` and `make sqlite3.c`; no Tcl or OpenSSL).
- The sources. Either add srclibs for `sqlcipher/sqlcipher` at tag `v4.20.0` (commit `355d4db92d3404e71faa8088d071a71d767807f4`) and `libtom/libtomcrypt` at tag `v1.18.2` (commit `7e7eb695d581782f04b24dc444cbfde86af59853`) and run `SQLCIPHER_SRC=$$sqlcipher$$ LIBTOMCRYPT_SRC=$$libtomcrypt$$ tool/prepare_foss.sh`, or allow the script to clone those tags itself. Either way it checks the commits and file hashes. Network is needed only in `prebuild`; the Gradle build compiles the generated C files and fetches nothing for SQLCipher.
- The NDK version the app's Gradle build uses, which compiles the library.

When `sqlite3` is upgraded and its prebuilt moves to a new SQLCipher, update the pins and hashes in `tool/foss/build_sqlcipher_sources.sh` to match, and the defines in `tool/prepare_foss.sh` if the `sqlite3` package's SQLCipher build changed them.

## Checking a build

The **Reproducible build** workflow does this on every change to `main` that touches the app, and on pull requests that change the Android build, the dependencies or the foss preparation. It builds the foss APKs twice, each time from a fresh copy of the checkout in F-Droid's build path, with the release flags and one throwaway key, and fails if the files differ. `tool/compare_apks.py` then names the entries that differ, and the run keeps both APKs for diffoscope.

It doesn't vary the Flutter SDK's location, the user or the machine, as F-Droid's builder will. Before the first F-Droid submission, also check by hand:

1. Build the release twice from a clean checkout of the same tag, in two fresh containers, with the same Flutter version, JDK and `SOURCE_DATE_EPOCH`.
2. Compare the unsigned APKs with `diffoscope`. Expect only the signature to differ.
3. To compare against a signed APK, copy the signature across with `apksigcopier compare signed.apk --unsigned unsigned.apk`. A match means the signed APK was built from this source.
4. Record any difference as an issue with the `reproducible-builds` label and the diffoscope output.
