import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';

/// How far back each institution's messages have been scanned, so the next
/// scan reads only what is new.
abstract interface class SmsScanMarksRepository {
  /// When [institutionId]'s last completed scan started, or null if never.
  Future<DateTime?> scannedUntil(String institutionId);

  Future<void> markScanned(String institutionId, DateTime until);

  /// Forgets every mark, so the next scan reads each account from the
  /// chosen start again. Messages already read are skipped by their hash.
  Future<void> clearAll();
}

class DriftSmsScanMarksRepository implements SmsScanMarksRepository {
  DriftSmsScanMarksRepository(this._db);

  final AppDatabase _db;

  static const _prefix = 'sms.scanned_until.';

  static String keyFor(String institutionId) => '$_prefix$institutionId';

  @override
  Future<void> clearAll() =>
      (_db.delete(_db.appSettings)..where((t) => t.key.like('$_prefix%'))).go();

  @override
  Future<DateTime?> scannedUntil(String institutionId) async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((t) => t.key.equals(keyFor(institutionId)))).getSingleOrNull();
    return row == null ? null : DateTime.tryParse(row.value);
  }

  @override
  Future<void> markScanned(String institutionId, DateTime until) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: keyFor(institutionId),
          value: until.toUtc().toIso8601String(),
        ),
      );
}

final smsScanMarksRepositoryProvider = Provider<SmsScanMarksRepository>(
  (ref) => DriftSmsScanMarksRepository(ref.watch(appDatabaseProvider)),
);
