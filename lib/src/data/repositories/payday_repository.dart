import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Which payday tasks the person ticked off, and whether they put the
/// checklist away, per month.
abstract interface class PaydayRepository {
  Future<Set<String>> ticked(YearMonth month);

  Future<void> setTicked(YearMonth month, String taskKey, bool done);

  Future<bool> isDismissed(YearMonth month);

  Future<void> dismiss(YearMonth month);
}

/// Keeps the checklist in app settings, one row per month for ticks and one
/// for dismissal.
class DriftPaydayRepository implements PaydayRepository {
  DriftPaydayRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  static String tickedKey(YearMonth month) => 'payday.${month.key}.ticked';

  static String dismissedKey(YearMonth month) =>
      'payday.${month.key}.dismissed';

  @override
  Future<Set<String>> ticked(YearMonth month) async {
    final value = await _read(tickedKey(month));
    if (value == null) return {};
    try {
      return {...(jsonDecode(value) as List).cast<String>()};
    } on FormatException {
      return {};
    }
  }

  @override
  Future<void> setTicked(YearMonth month, String taskKey, bool done) =>
      _db.transaction(() async {
        final keys = await ticked(month);
        if (done) {
          keys.add(taskKey);
        } else {
          keys.remove(taskKey);
        }
        await _write(tickedKey(month), jsonEncode(keys.toList()..sort()));
      });

  @override
  Future<bool> isDismissed(YearMonth month) async =>
      await _read(dismissedKey(month)) != null;

  @override
  Future<void> dismiss(YearMonth month) =>
      _write(dismissedKey(month), _clock().toUtc().toIso8601String());

  Future<String?> _read(String key) async => (await (_db.select(
    _db.appSettings,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> _write(String key, String value) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: key, value: value),
      );
}

final paydayRepositoryProvider = Provider<PaydayRepository>(
  (ref) => DriftPaydayRepository(ref.watch(appDatabaseProvider)),
);
