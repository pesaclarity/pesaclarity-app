import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/backup/backup.dart';
import 'key_value_store.dart';

/// Places a backup can be sent to automatically and restored from.
enum BackupLocationId {
  vault,
  drive,
  deviceFolder;

  static bool get _iPhone => defaultTargetPlatform == TargetPlatform.iOS;

  String get label => switch (this) {
    vault => 'Pesa Clarity vault',
    drive => 'My Google Drive',
    deviceFolder => _iPhone ? 'Files on this iPhone' : 'Phone or SD card',
  };

  /// Short form for summaries such as "Vault + SD card".
  String get shortLabel => switch (this) {
    vault => 'Vault',
    drive => 'Drive',
    deviceFolder => _iPhone ? 'Files' : 'SD card',
  };
}

/// A folder the user chose with the system picker.
final class DeviceFolder {
  const DeviceFolder({required this.uri, required this.name});

  final String uri;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is DeviceFolder && other.uri == uri && other.name == name;

  @override
  int get hashCode => Object.hash(uri, name);
}

/// Where backups go and when one last succeeded.
final class BackupSettings {
  const BackupSettings({
    this.isSetUp = false,
    this.enabled = const {},
    this.folder,
    this.lastSuccessAt,
    this.lastSuccessTo = const {},
  });

  /// Whether a passphrase and recovery key exist on this phone.
  final bool isSetUp;
  final Set<BackupLocationId> enabled;
  final DeviceFolder? folder;
  final DateTime? lastSuccessAt;
  final Set<BackupLocationId> lastSuccessTo;

  BackupSettings copyWith({
    bool? isSetUp,
    Set<BackupLocationId>? enabled,
    DeviceFolder? folder,
    DateTime? lastSuccessAt,
    Set<BackupLocationId>? lastSuccessTo,
  }) => BackupSettings(
    isSetUp: isSetUp ?? this.isSetUp,
    enabled: enabled ?? this.enabled,
    folder: folder ?? this.folder,
    lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
    lastSuccessTo: lastSuccessTo ?? this.lastSuccessTo,
  );
}

/// Reads and writes [BackupSettings] and the backup secrets.
///
/// Everything lives in secure storage rather than the database, so a restore
/// replaces the data without touching where backups go.
class BackupSettingsRepository {
  BackupSettingsRepository(this._store);

  final KeyValueStore _store;

  static const _settingsKey = 'pesaclarity.backup.settings.v1';
  static const _passphraseKey = 'pesaclarity.backup.passphrase.v1';
  static const _recoveryKeyKey = 'pesaclarity.backup.recovery.v1';

  Future<BackupSettings> load() async {
    final isSetUp = await readSecrets() != null;
    final raw = await _store.read(_settingsKey);
    if (raw == null) return BackupSettings(isSetUp: isSetUp);
    final Map<String, Object?> json;
    try {
      json = jsonDecode(raw) as Map<String, Object?>;
    } on Object {
      return BackupSettings(isSetUp: isSetUp);
    }
    Set<BackupLocationId> ids(Object? names) => {
      for (final name in (names as List<Object?>? ?? const []))
        for (final id in BackupLocationId.values)
          if (id.name == name) id,
    };
    final folderUri = json['folderUri'] as String?;
    final lastAt = json['lastSuccessAt'] as String?;
    return BackupSettings(
      isSetUp: isSetUp,
      enabled: ids(json['enabled']),
      folder: folderUri == null
          ? null
          : DeviceFolder(
              uri: folderUri,
              name: json['folderName'] as String? ?? 'Chosen folder',
            ),
      lastSuccessAt: lastAt == null ? null : DateTime.tryParse(lastAt),
      lastSuccessTo: ids(json['lastSuccessTo']),
    );
  }

  Future<void> save(BackupSettings settings) => _store.write(
    _settingsKey,
    jsonEncode({
      'enabled': [for (final id in settings.enabled) id.name],
      'folderUri': settings.folder?.uri,
      'folderName': settings.folder?.name,
      'lastSuccessAt': settings.lastSuccessAt?.toUtc().toIso8601String(),
      'lastSuccessTo': [for (final id in settings.lastSuccessTo) id.name],
    }),
  );

  /// The passphrase and recovery key new backups are written with.
  ///
  /// Kept on the phone so scheduled backups run without asking. The recovery
  /// key is never shown again after setup.
  Future<BackupSecrets?> readSecrets() async {
    final passphrase = await _store.read(_passphraseKey);
    final recovery = await _store.read(_recoveryKeyKey);
    if (passphrase == null || recovery == null) return null;
    try {
      return BackupSecrets(
        passphrase: passphrase,
        recoveryKey: RecoveryKey.fromBytes(base64Decode(recovery)),
      );
    } on Object {
      return null;
    }
  }

  Future<void> writeSecrets(BackupSecrets secrets) async {
    await _store.write(_passphraseKey, secrets.passphrase);
    await _store.write(
      _recoveryKeyKey,
      base64Encode(secrets.recoveryKey.bytes),
    );
  }
}

/// The passphrase and recovery key every new backup is encrypted for.
final class BackupSecrets {
  const BackupSecrets({required this.passphrase, required this.recoveryKey});

  final String passphrase;
  final RecoveryKey recoveryKey;

  @override
  String toString() => 'BackupSecrets(redacted)';
}
