import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Small JSON settings kept in the encrypted database's app settings table.
abstract interface class AppSettingsRepository {
  /// The JSON object saved under [key], or null when none is saved or it
  /// cannot be read.
  Future<Map<String, Object?>?> readJson(String key);

  Future<void> writeJson(String key, Map<String, Object?> value);
}

class DriftAppSettingsRepository implements AppSettingsRepository {
  DriftAppSettingsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<Map<String, Object?>?> readJson(String key) async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    if (row == null) return null;
    try {
      final decoded = jsonDecode(row.value);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeJson(String key, Map<String, Object?> value) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: key, value: jsonEncode(value)),
      );
}

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => DriftAppSettingsRepository(ref.watch(appDatabaseProvider)),
);
