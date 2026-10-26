import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/backup/backup.dart';
import 'package:pesaclarity/src/features/backup/application/backup_service.dart';
import 'package:pesaclarity/src/features/backup/data/backup_settings_repository.dart';
import 'package:pesaclarity/src/features/backup/data/key_value_store.dart';
import 'package:pesaclarity/src/features/backup/data/local_database_backup.dart';

import 'backup_fakes.dart';

const _fastKdf = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);
const _passphrase = 'John anapenda chai 2026';

Future<R> _inline<R>(FutureOr<R> Function() work) async => work();

void main() {
  late Directory work;
  late FakeLocalDataStore data;
  late BackupSettingsRepository settings;
  late BackupService service;
  final recoveryKey = RecoveryKey.generate();
  final now = DateTime(2026, 10, 26, 6, 10);

  setUp(() async {
    work = await Directory.systemTemp.createTemp('backup_service_test');
    data = FakeLocalDataStore(List.generate(3000, (i) => i % 200));
    settings = BackupSettingsRepository(MemoryKeyValueStore());
    await settings.writeSecrets(
      BackupSecrets(passphrase: _passphrase, recoveryKey: recoveryKey),
    );
    service = BackupService(
      data: data,
      settings: settings,
      workDirectory: () async => work,
      clock: () => now,
      kdfParams: _fastKdf,
      runner: _inline,
    );
  });
  tearDown(() => work.delete(recursive: true));

  test('backs up to every location and records the time', () async {
    final vault = MemoryLocation(BackupLocationId.vault);
    final folder = MemoryLocation(BackupLocationId.deviceFolder);
    final report = await service.backUp([vault, folder]);

    expect(report.succeeded, {
      BackupLocationId.vault,
      BackupLocationId.deviceFolder,
    });
    expect(vault.files.keys, ['pesaclarity-2026-10-26-0610.pcbackup']);
    expect(folder.files.values.single, vault.files.values.single);
    final saved = await settings.load();
    expect(saved.lastSuccessAt, now.toUtc());
    expect(saved.lastSuccessTo, report.succeeded);
    expect(work.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('one failing location does not stop the others', () async {
    final report = await service.backUp([
      MemoryLocation(BackupLocationId.vault, failWith: 'Offline'),
      MemoryLocation(BackupLocationId.deviceFolder),
    ]);
    expect(report.succeeded, {BackupLocationId.deviceFolder});
    expect(report.failed, {BackupLocationId.vault: 'Offline'});
    expect((await settings.load()).lastSuccessTo, {
      BackupLocationId.deviceFolder,
    });
  });

  test('nothing is recorded when every location fails', () async {
    await service.backUp([
      MemoryLocation(BackupLocationId.vault, failWith: 'Offline'),
    ]);
    expect((await settings.load()).lastSuccessAt, isNull);
  });

  test('refuses to back up before setup', () async {
    final fresh = BackupService(
      data: data,
      settings: BackupSettingsRepository(MemoryKeyValueStore()),
      workDirectory: () async => work,
      clock: () => now,
      runner: _inline,
    );
    expect(
      fresh.backUp([MemoryLocation(BackupLocationId.vault)]),
      throwsA(isA<BackupNotSetUpException>()),
    );
  });

  group('restore', () {
    late MemoryLocation folder;
    late List<int> original;

    setUp(() async {
      folder = MemoryLocation(BackupLocationId.deviceFolder);
      original = data.contents;
      await service.backUp([folder]);
      data.contents = [1, 2, 3];
    });

    Future<File> fetchLatest() async {
      final entries = await folder.list();
      return service.fetch(folder, entries.single);
    }

    test('with the passphrase replaces the data', () async {
      final manifest = await service.restoreFromFile(
        await fetchLatest(),
        const PassphraseCredential(_passphrase),
      );
      expect(manifest.createdAt, now.toUtc());
      expect(data.contents, original);
      expect(data.replacements, 1);
    });

    test('with the recovery key replaces the data', () async {
      await service.restoreFromFile(
        await fetchLatest(),
        RecoveryKeyCredential(recoveryKey),
      );
      expect(data.contents, original);
    });

    test('a wrong passphrase keeps the current data', () async {
      final file = await fetchLatest();
      await expectLater(
        service.restoreFromFile(file, const PassphraseCredential('chai')),
        throwsA(isA<WrongBackupCredentialException>()),
      );
      expect(data.contents, [1, 2, 3]);
      expect(data.replacements, 0);
      // The same file can be tried again.
      await service.restoreFromFile(
        file,
        const PassphraseCredential(_passphrase),
      );
      expect(data.contents, original);
    });

    test('a damaged file keeps the current data', () async {
      final file = await fetchLatest();
      final bytes = file.readAsBytesSync();
      bytes[bytes.length - 20] ^= 0xff;
      file.writeAsBytesSync(bytes);
      await expectLater(
        service.restoreFromFile(file, const PassphraseCredential(_passphrase)),
        throwsA(isA<BackupIntegrityException>()),
      );
      expect(data.replacements, 0);
    });

    test('a database check failure keeps the current data', () async {
      data.failReplaceWith = const RestoredDataException('damaged');
      await expectLater(
        service.restoreFromFile(
          await fetchLatest(),
          const PassphraseCredential(_passphrase),
        ),
        throwsA(isA<RestoredDataException>()),
      );
      expect(data.contents, [1, 2, 3]);
    });
  });
}
