import '../../core/money/money.dart';
import '../time/calendar.dart';
import 'activity_lines.dart';
import 'ledger_entry.dart';
import 'ledger_role.dart';
import 'ledger_totals.dart';

/// The type filter on Activity.
enum ActivityType {
  all('All types'),

  /// Spending and fees.
  spending('Spending only'),

  /// Spending in day-to-day categories, the money behind safe to spend.
  dayToDay('Day-to-day'),

  /// Money in, other than own transfers.
  moneyIn('Money in'),

  /// Moves between the user's own accounts.
  transfers('Own transfers');

  const ActivityType(this.label);

  final String label;

  /// Whether [entry] belongs under this type.
  bool matches(LedgerEntry entry) {
    final role = roleOf(entry);
    return switch (this) {
      all => true,
      spending => role == LedgerRole.spending || role == LedgerRole.fee,
      dayToDay => entry.isDailySpending && role == LedgerRole.spending,
      moneyIn => entry.isInflow && role != LedgerRole.ownTransfer,
      transfers => role == LedgerRole.ownTransfer,
    };
  }
}

/// What Activity shows: one account or all, a type, a search and an optional
/// date range (both ends included).
class ActivityFilter {
  const ActivityFilter({
    this.accountId,
    this.type = ActivityType.all,
    this.query = '',
    this.from,
    this.to,
  });

  /// Reads a filter from route query parameters, as written by [toQuery].
  /// Unknown or malformed values are ignored.
  factory ActivityFilter.fromQuery(Map<String, String> params) {
    final type = ActivityType.values
        .where((t) => t.name == params['type'])
        .firstOrNull;
    return ActivityFilter(
      accountId: int.tryParse(params['account'] ?? ''),
      type: type ?? ActivityType.all,
      from: parseCalendarDate(params['from']),
      to: parseCalendarDate(params['to']),
    );
  }

  final int? accountId;
  final ActivityType type;
  final String query;
  final CalendarDate? from;
  final CalendarDate? to;

  bool get hasDateRange => from != null || to != null;

  /// Route query parameters for this filter; the search is left out.
  Map<String, String> toQuery() => {
    if (accountId != null) 'account': '$accountId',
    if (type != ActivityType.all) 'type': type.name,
    if (from != null) 'from': formatCalendarDate(from!),
    if (to != null) 'to': formatCalendarDate(to!),
  };

  ActivityFilter copyWith({
    int? Function()? accountId,
    ActivityType? type,
    String? query,
    CalendarDate? Function()? from,
    CalendarDate? Function()? to,
  }) => ActivityFilter(
    accountId: accountId == null ? this.accountId : accountId(),
    type: type ?? this.type,
    query: query ?? this.query,
    from: from == null ? this.from : from(),
    to: to == null ? this.to : to(),
  );

  /// Whether [entry] passes every part of the filter. [labels] are the
  /// entry's category and account names, searched with its payee, the
  /// printed name, the number and the note.
  bool matches(LedgerEntry entry, {Iterable<String?> labels = const []}) {
    if (accountId != null && entry.accountId != accountId) return false;
    if (!type.matches(entry)) return false;
    final date = entry.date;
    if (from != null && date.isBefore(from!)) return false;
    if (to != null && date.isAfter(to!)) return false;
    return matchesSearch(entry, query, labels: labels);
  }
}

/// Whether [entry] matches the search [query]: case-insensitive text in its
/// payee, printed name, number, note or [labels], or digits in its amount.
bool matchesSearch(
  LedgerEntry entry,
  String query, {
  Iterable<String?> labels = const [],
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final texts = [
    entry.payeeName,
    entry.counterpartyName,
    entry.counterpartyValue,
    entry.note,
    ...labels,
  ];
  if (texts.any((t) => t != null && t.toLowerCase().contains(q))) return true;

  final digits = q.replaceAll(',', '');
  if (RegExp(r'^\d+(\.\d+)?$').hasMatch(digits)) {
    final major = entry.amountMinor ~/ 100;
    final minor = entry.amountMinor % 100;
    final amount = minor == 0
        ? '$major'
        : '$major.${minor.toString().padLeft(2, '0')}';
    return amount.contains(digits);
  }
  return false;
}

/// One day of the Activity feed.
class ActivityDay {
  const ActivityDay(this.date, this.lines);

  final CalendarDate date;

  /// Newest first.
  final List<ActivityLine> lines;
}

/// Builds the day-grouped Activity feed from [shown], newest day first.
///
/// Noise collapses to one line per day (see [collapseNoise]). An own
/// transfer appears once, as an [OwnTransferLine]: when both halves are in
/// [shown] only the outflow's place is used. [all] is used to find the
/// other half of a transfer that the filter left out.
List<ActivityDay> buildActivityFeed(
  Iterable<LedgerEntry> shown, {
  Iterable<LedgerEntry> all = const [],
}) {
  final list = shown.toList();
  final shownIds = {for (final e in list) e.id};
  final byId = {for (final e in all) e.id: e, for (final e in list) e.id: e};

  final kept = [
    for (final e in list)
      if (!(e.isInflow &&
          e.transferPairId != null &&
          shownIds.contains(e.transferPairId)))
        e,
  ];

  final days = <CalendarDate, List<ActivityLine>>{};
  final order = <CalendarDate>[];
  for (final line in collapseNoise(kept)) {
    final ActivityLine mapped;
    if (line is EntryLine && roleOf(line.entry) == LedgerRole.ownTransfer) {
      final entry = line.entry;
      final partner = byId[entry.transferPairId];
      mapped = entry.isOutflow
          ? OwnTransferLine(outflow: entry, inflow: partner)
          : OwnTransferLine(outflow: partner, inflow: entry);
    } else {
      mapped = line;
    }
    final date = CalendarDate.nairobi(line.occurredAt);
    final lines = days[date];
    if (lines == null) {
      days[date] = [mapped];
      order.add(date);
    } else {
      lines.add(mapped);
    }
  }
  return [for (final d in order) ActivityDay(d, List.unmodifiable(days[d]!))];
}

/// Money in and out for one week.
class WeekInOut {
  const WeekInOut({
    required this.start,
    required this.inMinor,
    required this.outMinor,
  });

  /// The Monday the week starts on.
  final CalendarDate start;

  /// Income; own transfers, borrowing and unnamed money stay out.
  final int inMinor;

  /// Spending and fees.
  final int outMinor;
}

/// The week to date containing [today], Monday first, from [history].
///
/// Totals follow [LedgerTotals], so own transfers are neither in nor out.
WeekInOut weekInOut(
  Iterable<LedgerEntry> history, {
  required CalendarDate today,
  String? currency,
}) {
  currency ??= BaseCurrency.code;
  final start = startOfWeek(today);
  final totals = LedgerTotals.of(
    history,
    from: start.startInstant,
    to: today.addDays(1).startInstant,
    currency: currency,
  );
  return WeekInOut(
    start: start,
    inMinor: totals.incomeMinor,
    outMinor: totals.spendingMinor + totals.feesMinor,
  );
}

/// The Monday on or before [date].
CalendarDate startOfWeek(CalendarDate date) =>
    date.addDays(-(date.weekday - DateTime.monday));

/// `2026-10-05` for 5 October 2026.
String formatCalendarDate(CalendarDate date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Reads a date written by [formatCalendarDate]; null when malformed.
CalendarDate? parseCalendarDate(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = CalendarDate(year, month, day);
  return date.month == month ? date : null;
}
