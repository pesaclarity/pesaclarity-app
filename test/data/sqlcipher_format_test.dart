import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pesaclarity/src/data/database/connection.dart';
import 'package:sqlite3/sqlite3.dart';

/// The play build's SQLCipher uses OpenSSL; the foss build compiles its own with
/// LibTomCrypt (tool/foss/sqlcipher.sh). Each must read the other's databases, since a
/// backup made with one can be restored with the other.
///
/// The fixtures are synthetic databases made by each build with [fixtureKey]: a
/// `rows` table of 300 rows, enough to span several pages.
const fixtureKey = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const fixtures = ['made-with-openssl.db', 'made-with-libtomcrypt.db'];

/// Set by CI to the provider the build under test should have.
const expectedProvider = String.fromEnvironment('EXPECT_CIPHER_PROVIDER');

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
    test('reads a database $name', () {
      final copy = p.join(dir.path, name);
      File(p.join('test', 'fixtures', 'sqlcipher', name)).copySync(copy);
      final db = open(copy, fixtureKey);
      addTearDown(db.close);
      expect(db.select('SELECT count(*) AS n FROM rows').single['n'], 300);
      expect(db.select('SELECT text FROM rows WHERE id = 300').single['text'], 'row 300');
      expect(db.select('PRAGMA cipher_integrity_check'), isEmpty);
    });
  }

  test('writes an encrypted file that only the key opens', () {
    final path = p.join(dir.path, 'new.db');
    final key = generateDatabaseKey();
    final db = open(path, key);
    db.execute('CREATE TABLE rows (id INTEGER PRIMARY KEY, text TEXT)');
    db.execute("INSERT INTO rows (text) VALUES ('kept')");
    db.close();

    final header = File(path).readAsBytesSync().sublist(0, 16);
    expect(String.fromCharCodes(header), isNot(startsWith('SQLite format 3')));

    final reopened = open(path, key);
    expect(reopened.select('SELECT text FROM rows').single['text'], 'kept');
    reopened.close();

    final wrong = open(path, generateDatabaseKey());
    addTearDown(wrong.close);
    expect(() => wrong.select('SELECT count(*) FROM rows'), throwsA(isA<SqliteException>()));
  });

  test('uses the expected crypto provider', () {
    final db = open(p.join(dir.path, 'provider.db'), generateDatabaseKey());
    addTearDown(db.close);
    final provider = db.select('PRAGMA cipher_provider').single.values.single;
    expect(provider, isIn(['openssl', 'libtomcrypt']));
    if (expectedProvider.isNotEmpty) expect(provider, expectedProvider);
  });
}
