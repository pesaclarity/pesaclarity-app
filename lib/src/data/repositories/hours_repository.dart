import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/hours/hours.dart';
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Hours logged for clients.
abstract interface class HoursRepository {
  Future<int> log({
    required String client,
    required String what,
    required CalendarDate day,
    required int minutes,
    required DateTime at,
    String? project,
    bool billable = true,
    int? rateMinor,
  });

  Future<void> update(HourEntry entry);

  Future<void> remove(int id);

  /// Entries on days `[from, to)`, by day then as logged.
  Future<List<HourEntry>> between(CalendarDate from, CalendarDate to);

  /// Billable entries not on an invoice yet, oldest first.
  Future<List<HourEntry>> unbilled({String? client});

  /// The rate last used for [client] and [project], or for [client].
  Future<int?> lastRate(String client, {String? project});

  /// Clients and their projects, most recent first.
  Future<Map<String, List<String>>> clientsAndProjects();

  /// Marks [ids] as billed on invoice [invoiceId]; null clears it.
  Future<void> setInvoice(Iterable<int> ids, int? invoiceId);
}

class DriftHoursRepository implements HoursRepository {
  DriftHoursRepository(this._db);

  final AppDatabase _db;

  HourEntry _entry(HourEntryRecord r) => HourEntry(
    id: r.id,
    client: r.client,
    project: r.project,
    what: r.what,
    day: CalendarDate.local(r.day),
    minutes: r.minutes,
    billable: r.billable,
    rateMinor: r.rateMinor,
    invoiceId: r.invoiceId,
  );

  @override
  Future<int> log({
    required String client,
    required String what,
    required CalendarDate day,
    required int minutes,
    required DateTime at,
    String? project,
    bool billable = true,
    int? rateMinor,
  }) => _db
      .into(_db.hourEntries)
      .insert(
        HourEntriesCompanion.insert(
          client: client.trim(),
          project: Value(_orNull(project)),
          what: what.trim(),
          day: day.startInstant,
          minutes: minutes,
          billable: Value(billable),
          rateMinor: Value(rateMinor),
          createdAt: at,
        ),
      );

  @override
  Future<void> update(HourEntry e) =>
      (_db.update(_db.hourEntries)..where((h) => h.id.equals(e.id))).write(
        HourEntriesCompanion(
          client: Value(e.client.trim()),
          project: Value(_orNull(e.project)),
          what: Value(e.what.trim()),
          day: Value(e.day.startInstant),
          minutes: Value(e.minutes),
          billable: Value(e.billable),
          rateMinor: Value(e.rateMinor),
        ),
      );

  @override
  Future<void> remove(int id) =>
      (_db.delete(_db.hourEntries)..where((h) => h.id.equals(id))).go();

  @override
  Future<List<HourEntry>> between(CalendarDate from, CalendarDate to) async => [
    for (final r
        in await (_db.select(_db.hourEntries)
              ..where(
                (h) =>
                    h.day.isBiggerOrEqualValue(from.startInstant) &
                    h.day.isSmallerThanValue(to.startInstant),
              )
              ..orderBy([
                (h) => OrderingTerm.asc(h.day),
                (h) => OrderingTerm.asc(h.id),
              ]))
            .get())
      _entry(r),
  ];

  @override
  Future<List<HourEntry>> unbilled({String? client}) async {
    final rows =
        await (_db.select(_db.hourEntries)
              ..where((h) => h.billable.equals(true) & h.invoiceId.isNull())
              ..orderBy([(h) => OrderingTerm.asc(h.day)]))
            .get();
    final key = client?.trim().toLowerCase();
    return [
      for (final r in rows)
        if (key == null || r.client.trim().toLowerCase() == key) _entry(r),
    ];
  }

  @override
  Future<int?> lastRate(String client, {String? project}) async {
    final rows =
        await (_db.select(_db.hourEntries)
              ..where((h) => h.rateMinor.isNotNull())
              ..orderBy([(h) => OrderingTerm.desc(h.id)]))
            .get();
    final c = client.trim().toLowerCase();
    final p = _orNull(project)?.toLowerCase();
    bool sameClient(HourEntryRecord r) => r.client.trim().toLowerCase() == c;
    return rows
            .where(
              (r) => sameClient(r) && (r.project?.trim().toLowerCase() == p),
            )
            .firstOrNull
            ?.rateMinor ??
        rows.where(sameClient).firstOrNull?.rateMinor;
  }

  @override
  Future<Map<String, List<String>>> clientsAndProjects() async {
    final rows = await (_db.select(
      _db.hourEntries,
    )..orderBy([(h) => OrderingTerm.desc(h.id)])).get();
    final out = <String, List<String>>{};
    for (final r in rows) {
      final projects = out.putIfAbsent(r.client, () => []);
      final p = r.project;
      if (p != null && !projects.contains(p)) projects.add(p);
    }
    return out;
  }

  @override
  Future<void> setInvoice(Iterable<int> ids, int? invoiceId) =>
      (_db.update(_db.hourEntries)..where((h) => h.id.isIn(ids))).write(
        HourEntriesCompanion(invoiceId: Value(invoiceId)),
      );
}

String? _orNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

final hoursRepositoryProvider = Provider<HoursRepository>(
  (ref) => DriftHoursRepository(ref.watch(appDatabaseProvider)),
);
