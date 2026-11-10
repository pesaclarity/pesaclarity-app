import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/sales/tab.dart';
import '../../domain/stock/measure.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';
import 'stock_repository.dart';

/// Tabs: rounds added for a table or a person and paid together. Nothing
/// leaves stock until a tab is paid.
abstract interface class TabsRepository {
  /// Open tabs, the oldest first.
  Future<List<OpenTab>> open();

  /// Starts a tab called [name].
  Future<int> start(String name, {required DateTime at});

  /// Adds a round of [lines] to [tabId].
  Future<void> add(int tabId, List<SaleLine> lines, {required DateTime at});

  /// [tabId]'s lines, in the order they were added.
  Future<List<TabLine>> lines(int tabId);

  /// [tabId] was paid, or with nothing on it, is dropped.
  Future<void> close(int tabId, {required DateTime at});

  /// Thousandths of each item's own unit on open tabs, by item.
  Future<Map<int, int>> held();
}

class DriftTabsRepository implements TabsRepository {
  DriftTabsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<OpenTab>> open() async {
    final tabs =
        await (_db.select(_db.tabs)
              ..where((t) => t.closedAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.openedAt)]))
            .get();
    if (tabs.isEmpty) return const [];
    final lines = await (_db.select(
      _db.tabLines,
    )..where((l) => l.tabId.isIn([for (final t in tabs) t.id]))).get();
    return [
      for (final t in tabs)
        OpenTab(
          id: t.id,
          name: t.name,
          openedAt: t.openedAt,
          quantityMilli: lines
              .where((l) => l.tabId == t.id)
              .fold(0, (sum, l) => sum + l.quantityMilli),
          totalMinor: lines
              .where((l) => l.tabId == t.id)
              .fold(0, (sum, l) => sum + l.totalMinor),
        ),
    ];
  }

  @override
  Future<int> start(String name, {required DateTime at}) => _db
      .into(_db.tabs)
      .insert(TabsCompanion.insert(name: name.trim(), openedAt: at));

  @override
  Future<void> add(int tabId, List<SaleLine> lines, {required DateTime at}) =>
      _db.batch((b) {
        b.insertAll(_db.tabLines, [
          for (final l in lines)
            TabLinesCompanion.insert(
              tabId: tabId,
              at: at,
              itemId: Value(l.itemId),
              measureId: Value(l.measureId),
              name: l.name,
              quantityMilli: l.quantityMilli,
              totalMinor: l.totalMinor,
            ),
        ]);
      });

  @override
  Future<List<TabLine>> lines(int tabId) async => [
    for (final l
        in await (_db.select(_db.tabLines)
              ..where((l) => l.tabId.equals(tabId))
              ..orderBy([(l) => OrderingTerm.asc(l.id)]))
            .get())
      TabLine(
        id: l.id,
        at: l.at,
        itemId: l.itemId,
        measureId: l.measureId,
        name: l.name,
        quantityMilli: l.quantityMilli,
        totalMinor: l.totalMinor,
      ),
  ];

  @override
  Future<void> close(int tabId, {required DateTime at}) async {
    final lines = await this.lines(tabId);
    if (lines.isEmpty) {
      await (_db.delete(_db.tabs)..where((t) => t.id.equals(tabId))).go();
      return;
    }
    await (_db.update(_db.tabs)..where((t) => t.id.equals(tabId))).write(
      TabsCompanion(closedAt: Value(at)),
    );
  }

  @override
  Future<Map<int, int>> held() async {
    final query = _db.select(_db.tabLines).join([
      innerJoin(_db.tabs, _db.tabs.id.equalsExp(_db.tabLines.tabId)),
      leftOuterJoin(
        _db.itemMeasures,
        _db.itemMeasures.id.equalsExp(_db.tabLines.measureId),
      ),
    ])..where(_db.tabs.closedAt.isNull() & _db.tabLines.itemId.isNotNull());
    final out = <int, int>{};
    for (final row in await query.get()) {
      final line = row.readTable(_db.tabLines);
      final m = row.readTableOrNull(_db.itemMeasures);
      final base = m == null
          ? line.quantityMilli
          : Measure(
              id: m.id,
              itemId: m.itemId,
              name: m.name,
              units: m.units,
              bases: m.bases,
            ).baseMilli(line.quantityMilli);
      out[line.itemId!] = (out[line.itemId!] ?? 0) + base;
    }
    return out;
  }
}

final tabsRepositoryProvider = Provider<TabsRepository>(
  (ref) => DriftTabsRepository(ref.watch(appDatabaseProvider)),
);
