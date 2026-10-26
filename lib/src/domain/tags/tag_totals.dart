import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../ledger/ledger_totals.dart';

/// A tag name tidied for storing: no leading `#`, lower case, single spaces.
/// Null when empty or longer than 40 characters.
String? cleanTagName(String raw) {
  final name = raw
      .trim()
      .replaceFirst(RegExp('^#+'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();
  if (name.isEmpty || name.length > 40) return null;
  return name;
}

/// Entries carrying [tagId].
Iterable<LedgerEntry> withTag(Iterable<LedgerEntry> entries, int tagId) =>
    entries.where((e) => e.tagIds.contains(tagId));

/// Spending net of refunds per category for entries in [currency] whose time
/// is in `[from, to)`. The null key is Uncategorised, so nothing drops out:
/// the values add up to [LedgerTotals.spendingMinor] for the same entries.
Map<int?, int> spendingByCategory(
  Iterable<LedgerEntry> entries, {
  required DateTime from,
  required DateTime to,
  String currency = 'KES',
}) {
  final totals = <int?, int>{};
  for (final entry in entries) {
    if (entry.currency != currency ||
        entry.occurredAt.isBefore(from) ||
        !entry.occurredAt.isBefore(to)) {
      continue;
    }
    final amount = switch (roleOf(entry)) {
      LedgerRole.spending => entry.amountMinor,
      LedgerRole.reversal when entry.isInflow => -entry.amountMinor,
      _ => 0,
    };
    if (amount != 0) {
      totals[entry.categoryId] = (totals[entry.categoryId] ?? 0) + amount;
    }
  }
  return totals;
}

/// Totals for one tag, for Insights.
class TagSummary {
  const TagSummary({
    required this.tagId,
    required this.entryCount,
    required this.totals,
    required this.spendingByCategory,
  });

  final int tagId;
  final int entryCount;
  final LedgerTotals totals;

  /// Null key is Uncategorised.
  final Map<int?, int> spendingByCategory;
}

/// One summary per tag used by entries in [currency] in `[from, to)`, by tag
/// id. A transaction with several tags counts in full under each.
Map<int, TagSummary> tagTotals(
  Iterable<LedgerEntry> entries, {
  required DateTime from,
  required DateTime to,
  String currency = 'KES',
}) {
  final byTag = <int, List<LedgerEntry>>{};
  for (final entry in entries) {
    if (entry.currency != currency ||
        entry.occurredAt.isBefore(from) ||
        !entry.occurredAt.isBefore(to)) {
      continue;
    }
    for (final tag in entry.tagIds) {
      (byTag[tag] ??= []).add(entry);
    }
  }
  return {
    for (final MapEntry(key: tag, value: tagged) in byTag.entries)
      tag: TagSummary(
        tagId: tag,
        entryCount: tagged.length,
        totals: LedgerTotals.of(tagged, from: from, to: to, currency: currency),
        spendingByCategory: spendingByCategory(
          tagged,
          from: from,
          to: to,
          currency: currency,
        ),
      ),
  };
}
