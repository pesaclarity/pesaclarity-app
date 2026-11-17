import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pesaclarity/src/data/database/connection.dart';
import 'package:pesaclarity/src/data/database/database_key_store.dart';
import 'package:sqlite3/sqlite3.dart';

/// The play build uses package:sqlite3's prebuilt SQLCipher, which links
/// OpenSSL; the foss build compiles SQLCipher from source with LibTomCrypt
/// (tool/foss/build_sqlcipher_sources.sh). Each must open the other's
/// databases, since a backup made with one can be restored with the other.
///
/// The fixtures are synthetic: a `rows` table of 300 rows ('row 1' to
/// 'row 300'), enough for several pages, keyed with [fixtureKey]
/// (`PRAGMA key = "x'...'"`). One was made by each build's library.
const fixtureKey =
    '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const fixtures = ['made-with-openssl.db', 'made-with-libtomcrypt.db'];

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('sqlcipher-format'));
  tearDown(() => dir.deleteSync(recursive: true));

  Database open(String path, String key) {
    final db = sqlite3.open(path);
    applyCipherKey(db, key);
    return db;
  }

  for (final name in fixtures) {
    test('opens $name', () {
      final copy = p.join(dir.path, name);
      File(p.join('test', 'fixtures', 'sqlcipher', name)).copySync(copy);
      final db = open(copy, fixtureKey);
      addTearDown(db.close);
      expect(db.select('SELECT count(*) AS n FROM rows').single['n'], 300);
      expect(
        db.select('SELECT text FROM rows WHERE id = 300').single['text'],
        'row 300',
      );
      expect(db.select('PRAGMA cipher_integrity_check'), isEmpty);
    });
  }

  test('the foss build pins the SQLCipher release this build uses', () {
    // When package:sqlite3 moves its prebuilt to a new SQLCipher, update the
    // pins in tool/foss/build_sqlcipher_sources.sh to match.
    final script = File('tool/foss/build_sqlcipher_sources.sh')
        .readAsStringSync();
    final pinned = RegExp(
      r'^SQLCIPHER_VERSION=(\S+)$',
      multiLine: true,
    ).firstMatch(script)!.group(1);
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final version = db.select('PRAGMA cipher_version').single.values.single;
    expect(version, startsWith('$pinned '));
  });

  test('uses the SQLCipher 4 defaults both builds share', () {
    final db = open(p.join(dir.path, 'settings.db'), generateDatabaseKey());
    addTearDown(db.close);
    String pragma(String name) =>
        db.select('PRAGMA $name').single.values.single.toString();

    expect(pragma('cipher_version'), startsWith('4.'));
    expect(pragma('cipher_provider'), isIn(['openssl', 'libtomcrypt']));
    expect(pragma('cipher_page_size'), '4096');
    expect(pragma('kdf_iter'), '256000');
    expect(pragma('cipher_hmac_algorithm'), 'HMAC_SHA512');
    expect(pragma('cipher_kdf_algorithm'), 'PBKDF2_HMAC_SHA512');
    expect(pragma('cipher_use_hmac'), '1');
    expect(pragma('cipher_plaintext_header_size'), '0');
  });

  test('writes a file that only its key opens', () {
    final path = p.join(dir.path, 'new.db');
    final key = generateDatabaseKey();
    final db = open(path, key);
    db.execute('CREATE TABLE rows (id INTEGER PRIMARY KEY, text TEXT)');
    db.execute("INSERT INTO rows (text) VALUES ('kept')");
    db.close();

    final header = String.fromCharCodes(File(path).readAsBytesSync().take(16));
    expect(header, isNot(startsWith('SQLite format 3')));

    final reopened = open(path, key);
    expect(reopened.select('SELECT text FROM rows').single['text'], 'kept');
    reopened.close();

    final wrong = open(path, generateDatabaseKey());
    addTearDown(wrong.close);
    expect(
      () => wrong.select('SELECT count(*) FROM rows'),
      throwsA(isA<SqliteException>()),
    );
  });
}
