import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// A closed day: what the drawer should have held and what was counted.
class DayClose {
  const DayClose({
    required this.day,
    required this.expectedMinor,
    required this.countedMinor,
    this.note,
  });

  final CalendarDate day;
  final int expectedMinor;
  final int countedMinor;
  final String? note;

  int get differenceMinor => countedMinor - expectedMinor;
}

/// A business's day closes, one a day.
abstract interface class DayClosesRepository {
  Future<DayClose?> on(CalendarDate day);

  /// Saves the close of [close]'s day, replacing an earlier one.
  Future<void> save(DayClose close, {required DateTime at});

  /// Closes from [from] on, newest first.
  Future<List<DayClose>> since(CalendarDate from);
}

class DriftDayClosesRepository implements DayClosesRepository {
  DriftDayClosesRepository(this._db);

  final AppDatabase _db;

  DayClose _close(DayCloseRecord r) => DayClose(
    day: CalendarDate.local(r.day),
    expectedMinor: r.expectedMinor,
    countedMinor: r.countedMinor,
    note: r.note,
  );

  @override
  Future<DayClose?> on(CalendarDate day) async {
    final r = await (_db.select(
      _db.dayCloses,
    )..where((d) => d.day.equals(day.startInstant))).getSingleOrNull();
    return r == null ? null : _close(r);
  }

  @override
  Future<void> save(DayClose close, {required DateTime at}) => _db
      .into(_db.dayCloses)
      .insert(
        DayClosesCompanion.insert(
          day: close.day.startInstant,
          expectedMinor: close.expectedMinor,
          countedMinor: close.countedMinor,
          note: Value(close.note),
          closedAt: at,
        ),
        onConflict: DoUpdate(
          (_) => DayClosesCompanion(
            expectedMinor: Value(close.expectedMinor),
            countedMinor: Value(close.countedMinor),
            note: Value(close.note),
            closedAt: Value(at),
          ),
          target: [_db.dayCloses.day],
        ),
      );

  @override
  Future<List<DayClose>> since(CalendarDate from) async => [
    for (final r
        in await (_db.select(_db.dayCloses)
              ..where((d) => d.day.isBiggerOrEqualValue(from.startInstant))
              ..orderBy([(d) => OrderingTerm.desc(d.day)]))
            .get())
      _close(r),
  ];
}

final dayClosesRepositoryProvider = Provider<DayClosesRepository>(
  (ref) => DriftDayClosesRepository(ref.watch(appDatabaseProvider)),
);
