import 'package:drift/drift.dart';

import '../../../data/database/app_database.dart';

/// Remembers that the modified-phone warning was dismissed, so it shows once.
abstract interface class DeviceWarningRepository {
  Future<bool> isDismissed();

  Future<void> dismiss();
}

class DriftDeviceWarningRepository implements DeviceWarningRepository {
  DriftDeviceWarningRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const dismissedAtKey = 'security.device_warning_dismissed_at';

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Future<bool> isDismissed() async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((t) => t.key.equals(dismissedAtKey))).getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> dismiss() => _db
      .into(_db.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          key: dismissedAtKey,
          value: _clock().toUtc().toIso8601String(),
        ),
        mode: InsertMode.insertOrIgnore,
      );
}
