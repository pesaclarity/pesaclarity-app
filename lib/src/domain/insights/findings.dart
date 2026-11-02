import '../../core/money/money.dart';
import '../ledger/activity_feed.dart';
import '../ledger/fuliza.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_totals.dart';
import '../time/calendar.dart';
import 'spending_charts.dart';

/// The smallest change in a category, in minor units, worth a finding.
const categoryFindingMinMinor = 50000;

/// One thing that changed this month, compared with the same days of last
/// month, and the transactions behind it.
sealed class Finding {
  const Finding({required this.nowMinor, required this.changeMinor});

  /// This month so far.
  final int nowMinor;

  /// [nowMinor] less the same days of last month.
  final int changeMinor;

  /// Activity showing the transactions behind this finding.
  ActivityFilter filterFor(CalendarDate today);
}

/// Spending in one category, or without one, moved the most.
final class CategoryFinding extends Finding {
  const CategoryFinding({
    required this.slice,
    required super.nowMinor,
    required super.changeMinor,
  });

  /// A [CategorySlice] or [UncategorisedSlice].
  final SliceKey slice;

  @override
  ActivityFilter filterFor(CalendarDate today) {
    final month = _monthSoFar(today);
    final s = slice;
    return s is CategorySlice
        ? month.copyWith(categoryId: () => s.categoryId)
        : month.copyWith(uncategorised: true);
  }
}

/// Fees this month.
final class FeesFinding extends Finding {
  const FeesFinding({required super.nowMinor, required super.changeMinor});

  @override
  ActivityFilter filterFor(CalendarDate today) =>
      _monthSoFar(today).copyWith(type: ActivityType.fees);
}

/// Money in this month.
final class IncomeFinding extends Finding {
  const IncomeFinding({required super.nowMinor, required super.changeMinor});

  @override
  ActivityFilter filterFor(CalendarDate today) =>
      _monthSoFar(today).copyWith(type: ActivityType.moneyIn);
}

ActivityFilter _monthSoFar(CalendarDate today) =>
    ActivityFilter(from: today.yearMonth.firstDay, to: today);

/// Up to three findings for the month to [today]: the category that moved
/// most, fees and money in, each against the same days of last month.
List<Finding> findingsFor(
  Iterable<LedgerEntry> history, {
  required CalendarDate today,
  String? currency,
}) {
  currency ??= BaseCurrency.code;
  final all = history.where((e) => e.currency == currency).toList();
  final fuliza = FulizaLedger.of(all);

  final start = today.yearMonth.firstDay;
  final end = today.addDays(1);
  final lastMonth = today.yearMonth.previous;
  final lastStart = lastMonth.firstDay;
  final lastDays = today.day < lastMonth.dayCount
      ? today.day
      : lastMonth.dayCount;
  final lastEnd = lastStart.addDays(lastDays);

  bool inRange(CalendarDate d, CalendarDate from, CalendarDate to) =>
      !d.isBefore(from) && d.isBefore(to);

  final now = <SliceKey, int>{};
  final before = <SliceKey, int>{};
  for (final entry in all) {
    final date = entry.date;
    final Map<SliceKey, int> bucket;
    if (inRange(date, start, end)) {
      bucket = now;
    } else if (inRange(date, lastStart, lastEnd)) {
      bucket = before;
    } else {
      continue;
    }
    for (final (key, amount) in spendingPartsOf(entry, fuliza)) {
      bucket[key] = (bucket[key] ?? 0) + amount;
    }
  }

  final findings = <Finding>[];

  CategoryFinding? biggest;
  for (final key in {...now.keys, ...before.keys}) {
    if (key is! CategorySlice && key is! UncategorisedSlice) continue;
    final change = (now[key] ?? 0) - (before[key] ?? 0);
    if (change.abs() < categoryFindingMinMinor) continue;
    if (biggest == null || change.abs() > biggest.changeMinor.abs()) {
      biggest = CategoryFinding(
        slice: key,
        nowMinor: now[key] ?? 0,
        changeMinor: change,
      );
    }
  }
  if (biggest != null) findings.add(biggest);

  const fees = FeesSlice();
  final feesNow = now[fees] ?? 0;
  if (feesNow > 0) {
    findings.add(
      FeesFinding(
        nowMinor: feesNow,
        changeMinor: feesNow - (before[fees] ?? 0),
      ),
    );
  }

  int income(CalendarDate from, CalendarDate to) => LedgerTotals.of(
    all,
    from: from.startInstant,
    to: to.startInstant,
    currency: currency,
  ).incomeMinor;
  final incomeNow = income(start, end);
  final incomeBefore = income(lastStart, lastEnd);
  if (incomeNow > 0 || incomeBefore > 0) {
    findings.add(
      IncomeFinding(nowMinor: incomeNow, changeMinor: incomeNow - incomeBefore),
    );
  }
  return findings;
}
