import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/tabs_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/sales/tab.dart';

/// Open tabs, the oldest first, following every change.
final openTabsProvider = FutureProvider<List<OpenTab>>((ref) {
  ref.watch(ledgerChangesProvider);
  return ref.watch(tabsRepositoryProvider).open();
});

/// One tab's lines, in the order they were added.
final tabLinesProvider = FutureProvider.family<List<TabLine>, int>((
  ref,
  tabId,
) {
  ref.watch(ledgerChangesProvider);
  return ref.watch(tabsRepositoryProvider).lines(tabId);
});

/// What open tabs hold of each item, in thousandths of its own unit.
final heldOnTabsProvider = FutureProvider<Map<int, int>>((ref) {
  ref.watch(ledgerChangesProvider);
  return ref.watch(tabsRepositoryProvider).held();
});
