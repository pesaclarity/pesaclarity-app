import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/books/books.dart';
import '../../domain/stock/stock.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// One line of a sale: an item and how much, or an amount typed in.
class SaleLine {
  const SaleLine({
    required this.name,
    required this.quantityMilli,
    required this.totalMinor,
    this.itemId,
  });

  final int? itemId;
  final String name;
  final int quantityMilli;
  final int totalMinor;
}

/// A change to an item's stock, for its history.
class StockMove {
  const StockMove({
    required this.at,
    required this.kind,
    required this.quantityMilli,
    required this.costMinor,
    this.reason,
    this.saleId,
  });

  final DateTime at;
  final StockMoveKind kind;
  final int quantityMilli;
  final int costMinor;
  final CountReason? reason;
  final int? saleId;
}

/// What a business sells, its stock and every change to it.
abstract interface class StockRepository {
  /// Items not archived, products first, then by name.
  Future<List<Item>> items();

  /// Adds an item. A product with [stockMilli] starts with that stock at
  /// [costMinor] a unit.
  Future<int> add({
    required ItemKind kind,
    required String name,
    required DateTime at,
    String? unit,
    int? priceMinor,
    int costMinor = 0,
    int stockMilli = 0,
    int? warnBelowMilli,
    String? grouping,
  });

  /// Saves [item]'s name, unit, price, warning and group.
  Future<void> update(Item item);

  /// Stock bought: [quantityMilli] for [paidMinor] in all. The average cost
  /// moves to take it in.
  Future<void> restock(
    int itemId, {
    required int quantityMilli,
    required int paidMinor,
    required DateTime at,
    int? recordId,
  });

  /// Takes sold [lines] of sale [saleId] out of stock at the average cost.
  Future<void> sold(int saleId, List<SaleLine> lines, {required DateTime at});

  /// The counted stock of [itemId] is [countedMilli]; the difference is kept
  /// for [reason].
  Future<void> count(
    int itemId, {
    required int countedMilli,
    required CountReason reason,
    required DateTime at,
  });

  /// [itemId]'s moves, newest first.
  Future<List<StockMove>> moves(int itemId);

  /// Sold quantities of [itemId] since [from].
  Future<int> soldSince(int itemId, DateTime from);

  /// Every stock move, for the books.
  Future<List<StockEntry>> stockEntries();
}

class DriftStockRepository implements StockRepository {
  DriftStockRepository(this._db);

  final AppDatabase _db;

  Item _item(ItemRecord r) => Item(
    id: r.id,
    kind: r.kind,
    name: r.name,
    unit: r.unit,
    priceMinor: r.priceMinor,
    stockMilli: r.stockMilli,
    averageCostMinor: r.averageCostMinor,
    warnBelowMilli: r.warnBelowMilli,
    grouping: r.grouping,
  );

  @override
  Future<List<Item>> items() async {
    final rows = await (_db.select(
      _db.items,
    )..where((i) => i.archived.equals(false))).get();
    final list = [for (final r in rows) _item(r)]
      ..sort((a, b) {
        if (a.kind != b.kind) return a.kind.index.compareTo(b.kind.index);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  Future<ItemRecord?> _row(int id) =>
      (_db.select(_db.items)..where((i) => i.id.equals(id))).getSingleOrNull();

  @override
  Future<int> add({
    required ItemKind kind,
    required String name,
    required DateTime at,
    String? unit,
    int? priceMinor,
    int costMinor = 0,
    int stockMilli = 0,
    int? warnBelowMilli,
    String? grouping,
  }) => _db.transaction(() async {
    final product = kind == ItemKind.product;
    final id = await _db
        .into(_db.items)
        .insert(
          ItemsCompanion.insert(
            kind: kind,
            name: name.trim(),
            unit: Value(unit?.trim().isEmpty ?? true ? null : unit!.trim()),
            priceMinor: Value(priceMinor),
            stockMilli: Value(product ? stockMilli : 0),
            averageCostMinor: Value(product ? costMinor : 0),
            warnBelowMilli: Value(product ? warnBelowMilli : null),
            grouping: Value(grouping),
          ),
        );
    if (product && stockMilli != 0) {
      await _move(
        id,
        at: at,
        kind: StockMoveKind.opening,
        quantityMilli: stockMilli,
        costMinor: costOf(stockMilli, costMinor),
      );
    }
    return id;
  });

  Future<void> _move(
    int itemId, {
    required DateTime at,
    required StockMoveKind kind,
    required int quantityMilli,
    required int costMinor,
    int? saleId,
    int? recordId,
    CountReason? reason,
  }) => _db
      .into(_db.stockMoves)
      .insert(
        StockMovesCompanion.insert(
          itemId: itemId,
          at: at,
          kind: kind,
          quantityMilli: quantityMilli,
          costMinor: costMinor,
          saleId: Value(saleId),
          recordId: Value(recordId),
          reason: Value(reason),
        ),
      );

  @override
  Future<void> update(Item item) =>
      (_db.update(_db.items)..where((i) => i.id.equals(item.id))).write(
        ItemsCompanion(
          name: Value(item.name.trim()),
          unit: Value(item.unit),
          priceMinor: Value(item.priceMinor),
          warnBelowMilli: Value(item.warnBelowMilli),
          grouping: Value(item.grouping),
        ),
      );

  @override
  Future<void> restock(
    int itemId, {
    required int quantityMilli,
    required int paidMinor,
    required DateTime at,
    int? recordId,
  }) => _db.transaction(() async {
    final r = await _row(itemId);
    if (r == null) return;
    final average = newAverageCost(
      stockMilli: r.stockMilli,
      averageMinor: r.averageCostMinor,
      quantityMilli: quantityMilli,
      paidMinor: paidMinor,
    );
    await (_db.update(_db.items)..where((i) => i.id.equals(itemId))).write(
      ItemsCompanion(
        stockMilli: Value(r.stockMilli + quantityMilli),
        averageCostMinor: Value(average),
      ),
    );
    await _move(
      itemId,
      at: at,
      kind: StockMoveKind.restocked,
      quantityMilli: quantityMilli,
      costMinor: paidMinor,
      recordId: recordId,
    );
  });

  @override
  Future<void> sold(int saleId, List<SaleLine> lines, {required DateTime at}) =>
      _db.transaction(() async {
        for (final line in lines) {
          await _db
              .into(_db.saleLines)
              .insert(
                SaleLinesCompanion.insert(
                  saleId: saleId,
                  itemId: Value(line.itemId),
                  name: line.name,
                  quantityMilli: line.quantityMilli,
                  totalMinor: line.totalMinor,
                ),
              );
          final id = line.itemId;
          if (id == null) continue;
          final r = await _row(id);
          if (r == null || r.kind != ItemKind.product) continue;
          await (_db.update(_db.items)..where((i) => i.id.equals(id))).write(
            ItemsCompanion(
              stockMilli: Value(r.stockMilli - line.quantityMilli),
            ),
          );
          await _move(
            id,
            at: at,
            kind: StockMoveKind.sold,
            quantityMilli: -line.quantityMilli,
            costMinor: costOf(line.quantityMilli, r.averageCostMinor),
            saleId: saleId,
          );
        }
      });

  @override
  Future<void> count(
    int itemId, {
    required int countedMilli,
    required CountReason reason,
    required DateTime at,
  }) => _db.transaction(() async {
    final r = await _row(itemId);
    if (r == null) return;
    final difference = countedMilli - r.stockMilli;
    if (difference == 0) return;
    await (_db.update(_db.items)..where((i) => i.id.equals(itemId))).write(
      ItemsCompanion(stockMilli: Value(countedMilli)),
    );
    await _move(
      itemId,
      at: at,
      kind: StockMoveKind.counted,
      quantityMilli: difference,
      costMinor: costOf(difference.abs(), r.averageCostMinor),
      reason: reason,
    );
  });

  @override
  Future<List<StockMove>> moves(int itemId) async => [
    for (final m
        in await (_db.select(_db.stockMoves)
              ..where((m) => m.itemId.equals(itemId))
              ..orderBy([(m) => OrderingTerm.desc(m.at)]))
            .get())
      StockMove(
        at: m.at,
        kind: m.kind,
        quantityMilli: m.quantityMilli,
        costMinor: m.costMinor,
        reason: m.reason,
        saleId: m.saleId,
      ),
  ];

  @override
  Future<int> soldSince(int itemId, DateTime from) async {
    var sold = 0;
    for (final m
        in await (_db.select(_db.stockMoves)..where(
              (m) =>
                  m.itemId.equals(itemId) &
                  m.kind.equalsValue(StockMoveKind.sold) &
                  m.at.isBiggerOrEqualValue(from),
            ))
            .get()) {
      sold -= m.quantityMilli;
    }
    return sold;
  }

  @override
  Future<List<StockEntry>> stockEntries() async => [
    for (final m in await _db.select(_db.stockMoves).get())
      if (m.kind != StockMoveKind.restocked)
        StockEntry(
          moveId: m.id,
          at: m.at,
          kind: m.kind,
          costMinor: m.costMinor,
          up: m.quantityMilli > 0,
          reason: m.reason,
        ),
  ];
}

final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => DriftStockRepository(ref.watch(appDatabaseProvider)),
);
