import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../../core/backup/backup.dart';
import '../data/backup_location.dart';
import '../data/backup_settings_repository.dart';
import '../data/local_database_backup.dart';

/// Runs work in a background isolate. Tests pass one that runs inline.
typedef IsolateRunner = Future<R> Function<R>(FutureOr<R> Function() work);

Future<R> _runInIsolate<R>(FutureOr<R> Function() work) => Isolate.run(work);

/// What happened at each location during one backup.
final class BackupRunReport {
  const BackupRunReport({required this.succeeded, required this.failed});

  final Set<BackupLocationId> succeeded;
  final Map<BackupLocationId, String> failed;
}

/// Thrown when backing up before a passphrase and recovery key exist.
final class BackupNotSetUpException implements Exception {
  const BackupNotSetUpException();
}

/// Makes encrypted backup files and restores from them.
class BackupService {
  BackupService({
    required this._data,
    required this._settings,
    required this._workDirectory,
    required this._clock,
    this._kdfParams = KdfParams.recommended,
    IsolateRunner runner = _runInIsolate,
  }) : _run = runner;

  final LocalDataStore _data;
  final BackupSettingsRepository _settings;
  final Future<Directory> Function() _workDirectory;
  final DateTime Function() _clock;
  final KdfParams _kdfParams;
  final IsolateRunner _run;

  Future<Directory> _freshDirectory(String name) async {
    final dir = Directory(p.join((await _workDirectory()).path, name));
    if (dir.existsSync()) await dir.delete(recursive: true);
    return dir.create(recursive: true);
  }

  /// Writes an encrypted `.pcbackup` of the current data into [directory].
  Future<File> createBackupFile(Directory directory) async {
    final secrets = await _settings.readSecrets();
    if (secrets == null) throw const BackupNotSetUpException();
    final now = _clock();
    final output = File(p.join(directory.path, backupFileName(now)));
    final snapshot = await _data.snapshot(directory);
    try {
      final snapshotPath = snapshot.file.path;
      final keyHex = snapshot.keyHex;
      final schema = snapshot.schemaVersion;
      final outputPath = output.path;
      final passphrase = secrets.passphrase;
      final recoveryBytes = secrets.recoveryKey.bytes;
      final kdf = _kdfParams;
      final createdAt = now.toUtc();
      await _run(
        () => BackupFiles.write(
          snapshot: snapshotPath,
          snapshotKeyHex: keyHex,
          schemaVersion: schema,
          createdAt: createdAt,
          output: outputPath,
          passphrase: passphrase,
          recoveryKeyBytes: recoveryBytes,
          kdfParams: kdf,
        ),
      );
    } on Object {
      if (output.existsSync()) await output.delete();
      rethrow;
    } finally {
      if (snapshot.file.existsSync()) await snapshot.file.delete();
    }
    return output;
  }

  /// Backs up to every location in [locations] and records the time if at
  /// least one succeeded.
  Future<BackupRunReport> backUp(List<BackupLocation> locations) async {
    final dir = await _freshDirectory('outgoing');
    final succeeded = <BackupLocationId>{};
    final failed = <BackupLocationId, String>{};
    try {
      final file = await createBackupFile(dir);
      final name = p.basename(file.path);
      for (final location in locations) {
        try {
          await location.upload(file, name);
          succeeded.add(location.id);
        } on BackupLocationException catch (e) {
          failed[location.id] = e.message;
        } on IOException {
          failed[location.id] = 'The copy could not be saved there.';
        }
      }
    } finally {
      await dir.delete(recursive: true);
    }
    if (succeeded.isNotEmpty) {
      final current = await _settings.load();
      await _settings.save(
        current.copyWith(lastSuccessAt: _clock(), lastSuccessTo: succeeded),
      );
    }
    return BackupRunReport(succeeded: succeeded, failed: failed);
  }

  /// A fresh backup file to hand to the share sheet.
  ///
  /// It stays in the app's cache until the next share, so the receiving app
  /// can read it after the share sheet closes.
  Future<File> createShareCopy() async =>
      createBackupFile(await _freshDirectory('share'));

  /// Copies [entry] from [location] into a local file for [restoreFromFile].
  Future<File> fetch(BackupLocation location, BackupEntry entry) async {
    final dir = await _freshDirectory('incoming');
    final file = File(p.join(dir.path, 'restore.pcbackup'));
    await location.download(entry, file);
    return file;
  }

  /// Unlocks [backup] with [credential], checks every byte, and only then
  /// replaces the data on this phone.
  ///
  /// Throws [WrongBackupCredentialException] if the credential does not fit;
  /// the caller can ask again with the same file. Any other failure leaves
  /// the current data untouched.
  Future<BackupManifest> restoreFromFile(
    File backup,
    BackupCredential credential,
  ) async {
    final staged = File(
      p.join((await _freshDirectory('staged')).path, 'restored.sqlite'),
    );
    final backupPath = backup.path;
    final stagedPath = staged.path;
    try {
      final manifest = await _run(
        () => BackupFiles.read(
          backup: backupPath,
          credential: credential,
          stagedDatabase: stagedPath,
        ),
      );
      await _data.replaceWith(staged, manifest.databaseKeyHex);
      return manifest;
    } finally {
      if (staged.existsSync()) await staged.delete();
    }
  }

  /// Removes downloaded and shared files once they are no longer needed.
  Future<void> clearTemporaryFiles() async {
    for (final name in ['incoming', 'staged']) {
      final dir = Directory(p.join((await _workDirectory()).path, name));
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  }
}
