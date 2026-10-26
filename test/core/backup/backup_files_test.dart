import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pesaclarity/src/core/backup/backup.dart';

const _fastKdf = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);
const _passphrase = 'John anapenda chai 2026';
const _dbKey =
    '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

Future<(BackupManifest, Uint8List)> _decode(List<List<int>> pieces) async {
  final out = <int>[];
  final sink = StreamController<List<int>>();
  final collected = sink.stream.forEach(out.addAll);
  final manifest = await BackupPayload.decode(
    Stream.fromIterable(pieces),
    sink,
  );
  await sink.close();
  await collected;
  return (manifest, Uint8List.fromList(out));
}

Future<List<int>> _encode(BackupManifest manifest, List<int> db) async {
  final out = <int>[];
  await BackupPayload.encode(manifest, Stream.value(db)).forEach(out.addAll);
  return out;
}

void main() {
  final manifest = BackupManifest(
    createdAt: DateTime.utc(2026, 10, 26, 6, 10),
    schemaVersion: 7,
    databaseKeyHex: _dbKey,
    databaseBytes: 5000,
  );
  final db = List.generate(5000, (i) => i % 251);

  group('BackupPayload', () {
    test('round-trips the manifest and database bytes', () async {
      final bytes = await _encode(manifest, db);
      // Uneven pieces, splitting the prefix and manifest across reads.
      final pieces = [
        for (var i = 0; i < bytes.length; i += 7)
          bytes.sublist(i, i + 7 > bytes.length ? bytes.length : i + 7),
      ];
      final (decoded, out) = await _decode(pieces);
      expect(decoded.createdAt, manifest.createdAt);
      expect(decoded.schemaVersion, 7);
      expect(decoded.databaseKeyHex, _dbKey);
      expect(out, db);
    });

    test('a short database is reported as truncated', () async {
      final bytes = await _encode(manifest, db);
      expect(
        _decode([bytes.sublist(0, bytes.length - 10)]),
        throwsA(isA<BackupTruncatedException>()),
      );
    });

    test('other bytes are rejected', () {
      expect(
        _decode([List.filled(64, 7)]),
        throwsA(isA<BackupTamperedException>()),
      );
    });
  });

  group('BackupFiles', () {
    late Directory dir;
    late File snapshot;
    final recoveryKey = RecoveryKey.generate();

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('backup_files_test');
      snapshot = File(p.join(dir.path, 'snapshot.sqlite'))
        ..writeAsBytesSync(db);
    });
    tearDown(() => dir.delete(recursive: true));

    Future<File> write() async {
      final out = File(p.join(dir.path, 'out.pcbackup'));
      await BackupFiles.write(
        snapshot: snapshot.path,
        snapshotKeyHex: _dbKey,
        schemaVersion: 7,
        createdAt: DateTime.utc(2026, 10, 26),
        output: out.path,
        passphrase: _passphrase,
        recoveryKeyBytes: recoveryKey.bytes,
        kdfParams: _fastKdf,
      );
      return out;
    }

    test('restores with the passphrase or the recovery key', () async {
      final file = await write();
      expect(file.readAsBytesSync().sublist(0, 4), [0x50, 0x43, 0x42, 0x4b]);
      for (final credential in [
        const PassphraseCredential(_passphrase),
        RecoveryKeyCredential(recoveryKey),
      ]) {
        final staged = p.join(dir.path, 'staged.sqlite');
        final restored = await BackupFiles.read(
          backup: file.path,
          credential: credential,
          stagedDatabase: staged,
        );
        expect(restored.databaseKeyHex, _dbKey);
        expect(File(staged).readAsBytesSync(), db);
      }
    });

    test('a wrong passphrase leaves no staged file', () async {
      final file = await write();
      final staged = p.join(dir.path, 'staged.sqlite');
      await expectLater(
        BackupFiles.read(
          backup: file.path,
          credential: const PassphraseCredential('not it'),
          stagedDatabase: staged,
        ),
        throwsA(isA<WrongBackupCredentialException>()),
      );
      expect(File(staged).existsSync(), isFalse);
    });

    test('a changed byte fails and removes the staged file', () async {
      final file = await write();
      final bytes = file.readAsBytesSync();
      bytes[bytes.length - 100] ^= 1;
      file.writeAsBytesSync(bytes);
      final staged = p.join(dir.path, 'staged.sqlite');
      await expectLater(
        BackupFiles.read(
          backup: file.path,
          credential: const PassphraseCredential(_passphrase),
          stagedDatabase: staged,
        ),
        throwsA(isA<BackupIntegrityException>()),
      );
      expect(File(staged).existsSync(), isFalse);
    });
  });
}
