import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/backup/backup.dart';
import 'package:pesaclarity/src/features/backup/application/backup_labels.dart';
import 'package:pesaclarity/src/features/backup/data/backup_location.dart';
import 'package:pesaclarity/src/features/backup/data/backup_settings_repository.dart';
import 'package:pesaclarity/src/features/backup/data/key_value_store.dart';

void main() {
  group('BackupSettingsRepository', () {
    test('starts empty and not set up', () async {
      final settings = await BackupSettingsRepository(MemoryKeyValueStore())
          .load();
      expect(settings.isSetUp, isFalse);
      expect(settings.enabled, isEmpty);
      expect(settings.lastSuccessAt, isNull);
    });

    test('round-trips settings and secrets', () async {
      final store = MemoryKeyValueStore();
      final repo = BackupSettingsRepository(store);
      final key = RecoveryKey.generate();
      await repo.writeSecrets(
        BackupSecrets(passphrase: 'John anapenda chai', recoveryKey: key),
      );
      await repo.save(
        BackupSettings(
          enabled: const {BackupLocationId.deviceFolder},
          folder: const DeviceFolder(uri: 'content://tree/x', name: 'Backups'),
          lastSuccessAt: DateTime.utc(2026, 10, 26, 3, 10),
          lastSuccessTo: const {BackupLocationId.deviceFolder},
        ),
      );

      final loaded = await BackupSettingsRepository(store).load();
      expect(loaded.isSetUp, isTrue);
      expect(loaded.enabled, {BackupLocationId.deviceFolder});
      expect(loaded.folder?.name, 'Backups');
      expect(loaded.lastSuccessAt, DateTime.utc(2026, 10, 26, 3, 10));
      final secrets = await repo.readSecrets();
      expect(secrets?.passphrase, 'John anapenda chai');
      expect(secrets?.recoveryKey, key);
      expect(secrets.toString(), isNot(contains('chai')));
    });

    test('ignores unreadable stored settings', () async {
      final store = MemoryKeyValueStore()
        ..values['pesaclarity.backup.settings.v1'] = '{not json';
      final loaded = await BackupSettingsRepository(store).load();
      expect(loaded.enabled, isEmpty);
    });
  });

  group('labels', () {
    final now = DateTime(2026, 10, 26, 18);

    test('day and time', () {
      expect(
        backupTimeLabel(DateTime(2026, 10, 26, 6, 10), now),
        'today, 06:10',
      );
      expect(backupDayLabel(DateTime(2026, 10, 25, 23), now), 'yesterday');
      expect(backupDayLabel(DateTime(2026, 10, 12), now), '12 Oct');
      expect(backupDayLabel(DateTime(2025, 12, 31), now), '31 Dec 2025');
    });

    test('Profile summary names where the last backup went', () {
      expect(lastBackupSummary(const BackupSettings(), now), isNull);
      expect(
        lastBackupSummary(
          BackupSettings(
            lastSuccessAt: DateTime(2026, 10, 26, 6, 10),
            lastSuccessTo: const {
              BackupLocationId.deviceFolder,
              BackupLocationId.vault,
            },
          ),
          now,
        ),
        'Vault + SD card · today',
      );
    });

    test('file names carry the backup time', () {
      final at = DateTime(2026, 3, 4, 5, 6);
      expect(backupFileName(at), 'pesaclarity-2026-03-04-0506.pcbackup');
      expect(backupTimeFromName(backupFileName(at)), at);
      expect(backupTimeFromName('holiday.jpg'), isNull);
    });
  });
}
