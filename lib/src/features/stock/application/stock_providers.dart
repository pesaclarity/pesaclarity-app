import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/stock_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/stock/measure.dart';
import '../../../domain/stock/stock.dart';
import '../../../domain/time/calendar.dart';

/// Days of sales that set an item's usual pace.
const paceDays = 14;

/// What the open business sells, following every change.
final itemsProvider = FutureProvider<List<Item>>((ref) {
  ref.watch(ledgerChangesProvider);
  return ref.watch(stockRepositoryProvider).items();
});

/// One item's stock history, newest first.
final itemMovesProvider = FutureProvider.family<List<StockMove>, int>((
  ref,
  itemId,
) {
  ref.watch(ledgerChangesProvider);
  return ref.watch(stockRepositoryProvider).moves(itemId);
});

/// How much of an item sold in the last [paceDays], a day.
final itemPaceProvider = FutureProvider.family<double, int>((
  ref,
  itemId,
) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final sold = await ref
      .watch(stockRepositoryProvider)
      .soldSince(itemId, today.addDays(-paceDays + 1).startInstant);
  return sold / paceDays;
});

/// Every other way each item sells or is bought, by item, smallest first.
final measuresProvider = FutureProvider<Map<int, List<Measure>>>((ref) {
  ref.watch(ledgerChangesProvider);
  return ref.watch(stockRepositoryProvider).measures();
});
