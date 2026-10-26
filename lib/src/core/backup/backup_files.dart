import 'dart:io';

import 'backup_codec.dart';
import 'backup_header.dart';
import 'backup_payload.dart';
import 'recovery_key.dart';

/// File-to-file backup steps. Each takes only sendable arguments so it can
/// run in a background isolate with `Isolate.run`.
abstract final class BackupFiles {
  /// Encrypts the database [snapshot] (keyed with [snapshotKeyHex]) into
  /// [output] as a `.pcbackup` file.
  static Future<void> write({
    required String snapshot,
    required String snapshotKeyHex,
    required int schemaVersion,
    required DateTime createdAt,
    required String output,
    required String passphrase,
    required List<int> recoveryKeyBytes,
    KdfParams kdfParams = KdfParams.recommended,
  }) async {
    final source = File(snapshot);
    final manifest = BackupManifest(
      createdAt: createdAt,
      schemaVersion: schemaVersion,
      databaseKeyHex: snapshotKeyHex,
      databaseBytes: await source.length(),
    );
    final codec = BackupCodec(kdfParams: kdfParams);
    final sink = File(output).openWrite();
    try {
      await sink.addStream(
        codec.encrypt(
          BackupPayload.encode(manifest, source.openRead()),
          passphrase: passphrase,
          recoveryKey: RecoveryKey.fromBytes(recoveryKeyBytes),
        ),
      );
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  /// Unlocks [backup] with [credential], authenticates every chunk and writes
  /// the database it holds to [stagedDatabase].
  ///
  /// [stagedDatabase] is deleted if anything fails, so a partial file is never
  /// left behind for a caller to pick up by mistake.
  static Future<BackupManifest> read({
    required String backup,
    required BackupCredential credential,
    required String stagedDatabase,
  }) async {
    final file = File(backup);
    final staged = File(stagedDatabase);
    final unlocked = await BackupCodec().unlock(file.openRead(), credential);
    final sink = staged.openWrite();
    try {
      final manifest = await BackupPayload.decode(
        unlocked.decrypt(file.openRead()),
        sink,
      );
      await sink.flush();
      await sink.close();
      return manifest;
    } on Object {
      await sink.close();
      if (staged.existsSync()) await staged.delete();
      rethrow;
    }
  }
}
