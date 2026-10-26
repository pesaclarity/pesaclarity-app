import '../enums.dart';
import '../time/calendar.dart';
import 'ledger_entry.dart';

/// Small, frequent entries that Activity shows as one line per day.
enum NoiseGroup { fulizaDraws, fulizaRepayments, roundUps, charges, airtime }

/// The noise group of [kind], or null for entries shown on their own.
NoiseGroup? noiseGroupOf(TransactionKind kind) => switch (kind) {
  TransactionKind.fulizaDraw => NoiseGroup.fulizaDraws,
  TransactionKind.fulizaRepayment => NoiseGroup.fulizaRepayments,
  TransactionKind.roundUp => NoiseGroup.roundUps,
  TransactionKind.charge => NoiseGroup.charges,
  TransactionKind.airtime => NoiseGroup.airtime,
  _ => null,
};

/// One line in the Activity feed.
sealed class ActivityLine {
  const ActivityLine();

  /// The time the line sorts by.
  DateTime get occurredAt;
}

/// An entry shown on its own.
class EntryLine extends ActivityLine {
  const EntryLine(this.entry);

  final LedgerEntry entry;

  @override
  DateTime get occurredAt => entry.occurredAt;
}

/// All of one day's entries of a [NoiseGroup] on one account, in one currency
/// and direction.
class DailyNoiseLine extends ActivityLine {
  const DailyNoiseLine({
    required this.date,
    required this.group,
    required this.accountId,
    required this.currency,
    required this.direction,
    required this.entries,
  });

  final CalendarDate date;
  final NoiseGroup group;
  final int accountId;
  final String currency;
  final TransactionDirection direction;

  /// Newest first.
  final List<LedgerEntry> entries;

  int get count => entries.length;

  int get totalMinor => entries.fold(0, (sum, e) => sum + e.amountMinor);

  /// The newest entry's time, so the line sits where the day's last one did.
  @override
  DateTime get occurredAt => entries.first.occurredAt;
}

/// Builds the Activity feed, newest first, collapsing noise to one line per
/// Nairobi day.
///
/// A noise group collapses even when it has a single entry that day, so the
/// feed always reads the same way. Days follow Africa/Nairobi, so a charge at
/// 23:30 EAT and another at 00:30 EAT the next day land on different lines.
List<ActivityLine> collapseNoise(Iterable<LedgerEntry> entries) {
  final sorted = entries.toList()
    ..sort((a, b) {
      final byTime = b.occurredAt.compareTo(a.occurredAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });

  final order = <Object>[];
  final groups = <_NoiseKey, List<LedgerEntry>>{};
  for (final entry in sorted) {
    final group = noiseGroupOf(entry.kind);
    if (group == null) {
      order.add(EntryLine(entry));
      continue;
    }
    final _NoiseKey key = (
      entry.date,
      group,
      entry.accountId,
      entry.currency,
      entry.direction,
    );
    final members = groups[key];
    if (members == null) {
      groups[key] = [entry];
      order.add(key);
    } else {
      members.add(entry);
    }
  }

  return [
    for (final item in order)
      if (item is EntryLine)
        item
      else if (item is _NoiseKey)
        DailyNoiseLine(
          date: item.$1,
          group: item.$2,
          accountId: item.$3,
          currency: item.$4,
          direction: item.$5,
          entries: List.unmodifiable(groups[item]!),
        ),
  ];
}

typedef _NoiseKey = (
  CalendarDate,
  NoiseGroup,
  int,
  String,
  TransactionDirection,
);
