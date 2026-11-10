import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/exchange_rates.dart';
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Exchange rates kept day by day, so a transaction converts at the rates of
/// its day rather than today's.
abstract interface class RateHistoryRepository {
  Future<RateHistory> read();

  /// Keeps [rates] as [day]'s, unless that day already has rates: the first
  /// rates of a day stay, so amounts from that day keep their value.
  Future<void> keep(CalendarDate day, ExchangeRates rates);
}

class DriftRateHistoryRepository implements RateHistoryRepository {
  DriftRateHistoryRepository(this._db);

  final AppDatabase _db;

  @override
  Future<RateHistory> read() async {
    final rows = await _db.select(_db.rateSnapshots).get();
    return RateHistory([
      for (final row in rows)
        if (_parseDay(row.day) case final day?)
          if (_parseRates(row.rates) case final rates?) DayRates(day, rates),
    ]);
  }

  @override
  Future<void> keep(CalendarDate day, ExchangeRates rates) => _db
      .into(_db.rateSnapshots)
      .insert(
        RateSnapshotsCompanion.insert(
          day: day.toString(),
          rates: jsonEncode(rates.toJson()),
        ),
        mode: InsertMode.insertOrIgnore,
      );

  static CalendarDate? _parseDay(String text) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    if (match == null) return null;
    return CalendarDate(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  static ExchangeRates? _parseRates(String text) {
    try {
      final json = jsonDecode(text);
      return json is Map<String, Object?>
          ? ExchangeRates.fromSaved(json)
          : null;
    } on FormatException {
      return null;
    }
  }
}

/// Rates kept with the open space, as its currency settings are.
final rateHistoryRepositoryProvider = Provider<RateHistoryRepository>(
  (ref) => DriftRateHistoryRepository(ref.watch(appDatabaseProvider)),
);
