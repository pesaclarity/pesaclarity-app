import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/ledger/ledger_entry.dart';

/// The tag Activity is filtered to; null shows everything.
///
/// Activity passes it to `TransactionsRepository.watchRecent(tagId:)` or
/// `ledgerEntries(tagId:)`, or filters entries with [matchesTagFilter]. The
/// Activity export follows it too.
class TagFilter extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int? tagId) => state = tagId;
}

final activityTagFilterProvider = NotifierProvider<TagFilter, int?>(
  TagFilter.new,
);

/// Whether [entry] passes a filter on [tagId]; everything passes null.
bool matchesTagFilter(LedgerEntry entry, int? tagId) =>
    tagId == null || entry.tagIds.contains(tagId);
