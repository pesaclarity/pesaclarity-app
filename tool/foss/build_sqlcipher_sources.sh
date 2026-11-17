#!/usr/bin/env bash
# Produces the C sources the foss build compiles SQLCipher from, so the
# package:sqlite3 build hook compiles them (`source: source`) instead of
# downloading its prebuilt libsqlcipher. F-Droid accepts no prebuilt native
# libraries. tool/prepare_foss.sh runs this and points pubspec.yaml at the
# files listed in the output's sources.txt.
#
# Inputs are pinned below and checked:
# - SQLCipher, the release package:sqlite3 bundles in the play build. Its
#   amalgamation (sqlite3.c) is generated here with the tree's own build
#   (./configure --disable-tcl uses the bundled jimsh, so only a host C
#   compiler and make are needed) and must match SQLITE3_C_SHA256.
# - LibTomCrypt, the crypto provider. package:sqlite3 links a static OpenSSL
#   for its prebuilt; LibTomCrypt is plain C that the hook can compile with
#   the rest. Only the files SQLCipher uses are copied, and they must match
#   LIBTOMCRYPT_FILES_SHA256.
# The database format is the same: SQLCipher 4 defaults (AES-256-CBC,
# HMAC-SHA512, PBKDF2-HMAC-SHA512, 4096-byte pages) whichever provider runs.
#
# Sources come from SQLCIPHER_SRC and LIBTOMCRYPT_SRC when set (git checkouts
# of the pinned tags, e.g. F-Droid srclibs), otherwise the pinned tags are
# cloned from GitHub into a temporary directory.
#
# Usage: tool/foss/build_sqlcipher_sources.sh [output dir]
#        (default: tool/foss/sqlcipher in this checkout; git-ignored)
set -euo pipefail

SQLCIPHER_VERSION=4.19.0
SQLCIPHER_REPO=https://github.com/sqlcipher/sqlcipher.git
SQLCIPHER_COMMIT=c4b275a47932888216bade83aff2bbc73df0ff85 # tag v4.19.0
# SQLite 3.53.4 with SQLCipher 4.19.0.
SQLITE3_C_SHA256=8640c653acadf665cce6331646f60b5b74a4690746f2c4a2d8f688a0570a0c0c

LIBTOMCRYPT_VERSION=1.18.2
LIBTOMCRYPT_REPO=https://github.com/libtom/libtomcrypt.git
LIBTOMCRYPT_COMMIT=7e7eb695d581782f04b24dc444cbfde86af59853 # tag v1.18.2
# SHA-256 of `sha256sum` over the copied files (see files_digest below).
LIBTOMCRYPT_FILES_SHA256=092d065b3710b601e364102ff22436e8518bc02056fc583af48c70cf467e0864

# What SQLCipher's LibTomCrypt provider (src/crypto_libtomcrypt.c) links:
# AES in CBC mode, SHA-1/256/512, HMAC, PBKDF2 and the Fortuna PRNG, plus the
# descriptor tables and helpers they need.
LIBTOMCRYPT_SOURCES=(
  src/ciphers/aes/aes.c
  src/hashes/helper/hash_memory.c
  src/hashes/sha1.c
  src/hashes/sha2/sha256.c
  src/hashes/sha2/sha512.c
  src/mac/hmac/hmac_done.c
  src/mac/hmac/hmac_init.c
  src/mac/hmac/hmac_memory.c
  src/mac/hmac/hmac_process.c
  src/misc/compare_testvector.c
  src/misc/crypt/crypt_argchk.c
  src/misc/crypt/crypt_cipher_descriptor.c
  src/misc/crypt/crypt_cipher_is_valid.c
  src/misc/crypt/crypt_find_cipher.c
  src/misc/crypt/crypt_find_hash.c
  src/misc/crypt/crypt_hash_descriptor.c
  src/misc/crypt/crypt_hash_is_valid.c
  src/misc/crypt/crypt_prng_descriptor.c
  src/misc/crypt/crypt_register_cipher.c
  src/misc/crypt/crypt_register_hash.c
  src/misc/crypt/crypt_register_prng.c
  src/misc/pkcs5/pkcs_5_2.c
  src/misc/zeromem.c
  src/modes/cbc/cbc_decrypt.c
  src/modes/cbc/cbc_done.c
  src/modes/cbc/cbc_encrypt.c
  src/modes/cbc/cbc_start.c
  src/prngs/fortuna.c
  src/prngs/rng_get_bytes.c
)
# Included by aes.c rather than compiled on its own.
LIBTOMCRYPT_INCLUDED=(src/ciphers/aes/aes_tab.c)

root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${1:-$root/tool/foss/sqlcipher}"

fail() { echo "build_sqlcipher_sources: $*" >&2; exit 1; }

for tool in git cc make sha256sum tar; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# source_tree GIVEN_DIR REPO TAG COMMIT NAME: prints the path of a checkout of
# COMMIT: GIVEN_DIR when set, else a fresh clone of TAG.
source_tree() {
  local given="$1" repo="$2" tag="$3" commit="$4" name="$5"
  local dir
  if [ -n "$given" ]; then
    dir="$given"
    [ -d "$dir" ] || fail "$dir does not exist"
  else
    dir="$work/$name"
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" "$repo" "$dir" >&2
  fi
  if [ -e "$dir/.git" ]; then
    local head
    head="$(git -C "$dir" rev-parse HEAD)"
    [ "$head" = "$commit" ] || fail "$dir is at $head, expected $commit ($tag)"
  else
    echo "build_sqlcipher_sources: $dir is not a git checkout; relying on the file hashes" >&2
  fi
  echo "$dir"
}

# files_digest DIR FILE...: one SHA-256 over the listed files' SHA-256s.
files_digest() {
  local dir="$1"
  shift
  (cd "$dir" && LC_ALL=C sha256sum "$@") | sha256sum | cut -d' ' -f1
}

sqlcipher="$(source_tree "${SQLCIPHER_SRC:-}" "$SQLCIPHER_REPO" "v$SQLCIPHER_VERSION" "$SQLCIPHER_COMMIT" sqlcipher)"
libtomcrypt="$(source_tree "${LIBTOMCRYPT_SRC:-}" "$LIBTOMCRYPT_REPO" "v$LIBTOMCRYPT_VERSION" "$LIBTOMCRYPT_COMMIT" libtomcrypt)"

# SQLCipher amalgamation, generated in a copy so the source tree stays clean.
mkdir "$work/sqlcipher-build"
tar -C "$sqlcipher" --exclude=.git -cf - . | tar -C "$work/sqlcipher-build" -xf -
(
  cd "$work/sqlcipher-build"
  ./configure --disable-tcl >configure.log 2>&1 || { cat configure.log >&2; exit 1; }
  make sqlite3.c >make.log 2>&1 || { cat make.log >&2; exit 1; }
)
actual="$(sha256sum "$work/sqlcipher-build/sqlite3.c" | cut -d' ' -f1)"
[ "$actual" = "$SQLITE3_C_SHA256" ] ||
  fail "generated sqlite3.c has SHA-256 $actual, expected $SQLITE3_C_SHA256"

# LibTomCrypt: the sources listed above and all its headers.
mapfile -t headers < <(cd "$libtomcrypt" && find src/headers -name '*.h' | LC_ALL=C sort)
ltc_files=("${LIBTOMCRYPT_SOURCES[@]}" "${LIBTOMCRYPT_INCLUDED[@]}" "${headers[@]}" LICENSE)
actual="$(files_digest "$libtomcrypt" "${ltc_files[@]}")"
[ "$actual" = "$LIBTOMCRYPT_FILES_SHA256" ] ||
  fail "LibTomCrypt files have SHA-256 $actual, expected $LIBTOMCRYPT_FILES_SHA256"

rm -rf "$out"
mkdir -p "$out/libtomcrypt"
cp "$work/sqlcipher-build/sqlite3.c" "$out/sqlite3.c"
cp "$sqlcipher/LICENSE.md" "$out/SQLCIPHER-LICENSE.md"
(cd "$libtomcrypt" && tar -cf - "${ltc_files[@]}") | tar -C "$out/libtomcrypt" -xf -

# The C files to compile, relative to $out, for tool/prepare_foss.sh. Each is
# compiled on its own: LibTomCrypt's files reuse macro names, so they cannot
# share a translation unit.
{
  echo sqlite3.c
  for f in "${LIBTOMCRYPT_SOURCES[@]}"; do echo "libtomcrypt/$f"; done
} >"$out/sources.txt"

cat >"$out/README" <<EOF
Generated by tool/foss/build_sqlcipher_sources.sh; do not edit or commit.
sqlite3.c: SQLCipher $SQLCIPHER_VERSION amalgamation ($SQLCIPHER_COMMIT), SHA-256 $SQLITE3_C_SHA256
libtomcrypt/: LibTomCrypt $LIBTOMCRYPT_VERSION ($LIBTOMCRYPT_COMMIT), files SHA-256 $LIBTOMCRYPT_FILES_SHA256
EOF

echo "SQLCipher $SQLCIPHER_VERSION sources (LibTomCrypt $LIBTOMCRYPT_VERSION) in $out"
