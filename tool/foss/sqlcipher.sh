#!/usr/bin/env bash
# Builds SQLCipher from source for the foss build, so the APK carries no prebuilt
# library (F-Droid accepts none). By default package:sqlite3's build hook downloads a
# prebuilt SQLCipher; this makes the hook compile one instead, for each chip.
# Run by tool/prepare_foss.sh, on a throwaway checkout.
#
# - SQLCipher's single-file source (sqlite3.c) is made with SQLCipher's own build, from
#   the pinned commit below.
# - Its crypto comes from LibTomCrypt, compiled from source alongside it. The prebuilt
#   links OpenSSL, which the hook can't build for each chip. Databases are the same
#   format either way (SQLCipher 4 defaults), so backups move between builds.
# - The compile options are those of the prebuilt, so both builds behave the same.
#
# F-Droid's recipe can pass its own checkouts as SQLCIPHER_SRC and LIBTOMCRYPT_SRC;
# otherwise both are fetched. Either way the commits are checked.
#
# Usage: tool/foss/sqlcipher.sh   (from the checkout's root)
# Needs: git, a C compiler and make. SQLCipher's build uses tclsh if present, else its own.
set -euo pipefail

sqlcipher_url=https://github.com/sqlcipher/sqlcipher
sqlcipher_commit=c4b275a47932888216bade83aff2bbc73df0ff85     # v4.19.0, as the prebuilt
libtomcrypt_url=https://github.com/libtom/libtomcrypt
libtomcrypt_commit=7e7eb695d581782f04b24dc444cbfde86af59853   # v1.18.2

[ -f pubspec.yaml ] || { echo "Run from the checkout's root" >&2; exit 1; }
grep -q '^      source: sqlcipher$' pubspec.yaml ||
  { echo "pubspec.yaml has no 'source: sqlcipher' to replace" >&2; exit 1; }

out=third_party
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Copies the source at <commit> into <dest>: from <given> when set, else fetched.
fetch() {
  local url="$1" commit="$2" given="$3" dest="$4"
  if [ -n "$given" ]; then
    local head
    head="$(git -C "$given" rev-parse HEAD)"
    [ "$head" = "$commit" ] || { echo "$given is at $head, not $commit" >&2; exit 1; }
    cp -a "$given" "$dest"
  else
    git init -q "$dest"
    git -C "$dest" fetch -q --depth 1 "$url" "$commit"
    git -C "$dest" checkout -q FETCH_HEAD
  fi
  rm -rf "$dest/.git"
}

fetch "$sqlcipher_url" "$sqlcipher_commit" "${SQLCIPHER_SRC:-}" "$work/sqlcipher"
fetch "$libtomcrypt_url" "$libtomcrypt_commit" "${LIBTOMCRYPT_SRC:-}" "$work/libtomcrypt"

# The single file. The defines here only steer what goes into it; the build hook
# compiles it with the defines below.
(
  cd "$work/sqlcipher"
  ./configure --with-tempstore=yes \
    CFLAGS="-DSQLITE_HAS_CODEC -DSQLITE_EXTRA_INIT=sqlcipher_extra_init -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown" \
    > "$work/configure.log" 2>&1 || { tail -30 "$work/configure.log" >&2; exit 1; }
  make sqlite3.c > "$work/make.log" 2>&1 || { tail -30 "$work/make.log" >&2; exit 1; }
)

rm -rf "$out/sqlcipher" "$out/libtomcrypt"
mkdir -p "$out/sqlcipher" "$out/libtomcrypt"
cp "$work/sqlcipher/sqlite3.c" "$work/sqlcipher/LICENSE.md" "$out/sqlcipher/"
cp -a "$work/libtomcrypt/src" "$work/libtomcrypt/LICENSE" "$out/libtomcrypt/"

# Sorted, so every build compiles the same list in the same order.
mapfile -t ltc_sources < <(cd "$out" && find libtomcrypt/src -name '*.c' | LC_ALL=C sort)

# The prebuilt's compile options (PRAGMA compile_options): package:sqlite3's defaults
# without SQLITE_OMIT_TRACE, plus SQLCipher's own.
defines=(
  SQLITE_HAS_CODEC
  SQLCIPHER_CRYPTO_LIBTOMCRYPT
  SQLITE_EXTRA_INIT=sqlcipher_extra_init
  SQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown
  SQLITE_ENABLE_DBSTAT_VTAB
  SQLITE_ENABLE_FTS5
  SQLITE_ENABLE_RTREE
  SQLITE_ENABLE_MATH_FUNCTIONS
  SQLITE_DQS=0
  SQLITE_DEFAULT_MEMSTATUS=0
  SQLITE_TEMP_STORE=2
  SQLITE_MAX_EXPR_DEPTH=0
  SQLITE_STRICT_SUBTYPE=1
  SQLITE_OMIT_AUTHORIZATION
  SQLITE_OMIT_DECLTYPE
  SQLITE_OMIT_DEPRECATED
  SQLITE_OMIT_PROGRESS_CALLBACK
  SQLITE_OMIT_SHARED_CACHE
  SQLITE_OMIT_TCL_VARIABLE
  SQLITE_USE_ALLOCA
  SQLITE_ENABLE_SESSION
  SQLITE_ENABLE_PREUPDATE_HOOK
  SQLITE_UNTESTABLE
  SQLITE_HAVE_ISNAN
  SQLITE_HAVE_LOCALTIME_R
  SQLITE_HAVE_MALLOC_USABLE_SIZE
  SQLITE_HAVE_STRCHRNUL
  SQLITE_ENABLE_BATCH_ATOMIC_WRITE
)

# Drops LibTomCrypt code SQLCipher never calls, and hardens the library as the
# prebuilt is hardened.
flags=(
  -ffunction-sections
  -fdata-sections
  -Wl,--gc-sections
  -fstack-protector-strong
  -D_FORTIFY_SOURCE=2
  -Wl,-z,relro
  -Wl,-z,now
  -Wl,-z,noexecstack
)

hook="$work/hook.yaml"
{
  echo "      # tool/foss/sqlcipher.sh: SQLCipher built from source, with LibTomCrypt."
  echo "      source:"
  echo "        android: source"
  echo "        linux: source"
  echo "        default: sqlcipher"
  echo "      path:"
  echo "        - $out/sqlcipher/sqlite3.c"
  printf '        - %s\n' "${ltc_sources[@]/#/$out/}"
  echo "      additional_includes:"
  echo "        - $out/libtomcrypt/src/headers"
  echo "      additional_flags:"
  printf '        - "%s"\n' "${flags[@]}"
  echo "      defines:"
  echo "        default_options: false"
  echo "        defines:"
  printf '          - %s\n' "${defines[@]}"
} > "$hook"

awk -v hook="$hook" '
  /^      source: sqlcipher$/ { while ((getline line < hook) > 0) print line; next }
  { print }
' pubspec.yaml > "$work/pubspec.yaml"
mv "$work/pubspec.yaml" pubspec.yaml
grep -q '^        android: source$' pubspec.yaml ||
  { echo "Could not point package:sqlite3 at the SQLCipher source" >&2; exit 1; }

echo "SQLCipher $(cat "$work/sqlcipher/VERSION") from source, with LibTomCrypt (${#ltc_sources[@]} files)."
