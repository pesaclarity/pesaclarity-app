import '../enums.dart';
import '../time/calendar.dart';
import 'book_account.dart';
import 'books.dart';

/// The time a report covers: `[from, to)` in whole days.
class ReportPeriod {
  const ReportPeriod(this.from, this.to, this.label);

  /// This month to date.
  factory ReportPeriod.thisMonth(CalendarDate today) =>
      ReportPeriod(today.yearMonth.firstDay, today.addDays(1), 'This month');

  /// The whole of last month.
  factory ReportPeriod.lastMonth(CalendarDate today) {
    final month = today.yearMonth.previous;
    return ReportPeriod(month.firstDay, today.yearMonth.firstDay, 'Last month');
  }

  /// The last three months, this one included.
  factory ReportPeriod.threeMonths(CalendarDate today) => ReportPeriod(
    today.yearMonth.addMonths(-2).firstDay,
    today.addDays(1),
    '3 months',
  );

  final CalendarDate from;

  /// The day after the last day.
  final CalendarDate to;
  final String label;

  int get days => from.daysUntil(to);

  /// The same length of time just before.
  ReportPeriod get previous =>
      ReportPeriod(from.addDays(-days), from, 'Before');

  CalendarDate get lastDay => to.addDays(-1);

  @override
  bool operator ==(Object other) =>
      other is ReportPeriod &&
      other.from == from &&
      other.to == to &&
      other.label == label;

  @override
  int get hashCode => Object.hash(from, to, label);
}

/// The periods reports offer.
enum ReportRange {
  thisMonth('This month'),
  lastMonth('Last month'),
  threeMonths('3 months');

  const ReportRange(this.label);

  final String label;
}

/// The period [range] covers on [today].
ReportPeriod periodFor(ReportRange range, CalendarDate today) =>
    switch (range) {
      ReportRange.thisMonth => ReportPeriod.thisMonth(today),
      ReportRange.lastMonth => ReportPeriod.lastMonth(today),
      ReportRange.threeMonths => ReportPeriod.threeMonths(today),
    };

/// What [period] is compared with: the same days of the month before for a
/// month so far, the month or months before for whole months, else the same
/// length of time just before. Labelled for "up 9% on October".
ReportPeriod comparisonFor(ReportPeriod period) {
  final from = period.from;
  if (from.day != 1) return period.previous;
  final start = from.yearMonth;
  final whole = period.to.day == 1;
  final months = start.monthsUntil(period.to.yearMonth) + (whole ? 0 : 1);
  final before = start.addMonths(-months);
  final end = before.firstDay.addDays(period.days);
  return ReportPeriod(
    before.firstDay,
    whole || end.isAfter(from) ? from : end,
    months == 1 ? _monthNames[before.month - 1] : 'the $months months before',
  );
}

/// `1 to 30 November`, `1 September to 5 November`, with the year when it
/// is not [thisYear] or the period spans two.
String periodText(ReportPeriod period, {int? thisYear}) {
  final a = period.from;
  final b = period.lastDay;
  String day(CalendarDate d, {bool year = false}) =>
      '${d.day} ${_monthNames[d.month - 1]}${year ? ' ${d.year}' : ''}';
  final showYear = a.year != b.year || thisYear == null || b.year != thisYear;
  if (a == b) return day(a, year: showYear);
  if (a.year == b.year && a.month == b.month) {
    return '${a.day} to ${day(b, year: showYear)}';
  }
  return '${day(a, year: a.year != b.year)} to ${day(b, year: showYear)}';
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// One line of profit and loss.
class PnlLine {
  const PnlLine(this.name, this.amountMinor);

  final String name;
  final int amountMinor;
}

/// Income less costs, line by line.
class ProfitAndLoss {
  const ProfitAndLoss({required this.income, required this.costs});

  final List<PnlLine> income;
  final List<PnlLine> costs;

  int get incomeMinor => income.fold(0, (sum, l) => sum + l.amountMinor);
  int get costsMinor => costs.fold(0, (sum, l) => sum + l.amountMinor);
  int get profitMinor => incomeMinor - costsMinor;
}

/// What the business has and owes at the end of a period.
class BalanceSummary {
  const BalanceSummary({
    required this.moneyMinor,
    required this.owedToYouMinor,
    required this.owedToSuppliersMinor,
    required this.stockMinor,
    required this.paidYourselfMinor,
  });

  /// Cash, M-Pesa and bank.
  final int moneyMinor;
  final int owedToYouMinor;
  final int owedToSuppliersMinor;
  final int stockMinor;

  /// Taken out by the owner during the period.
  final int paidYourselfMinor;

  /// What the business is worth on its books: what it has, less what it
  /// owes.
  int get netMinor =>
      moneyMinor + owedToYouMinor + stockMinor - owedToSuppliersMinor;
}

/// Names for the fixed book accounts as reports print them.
String bookAccountName(BookAccount a, Map<int, String> categoryNames) =>
    switch (a.kind) {
      BookAccountKind.incomeCategory ||
      BookAccountKind.spendingCategory => categoryNames[a.id] ?? 'Other',
      BookAccountKind.uncategorisedIncome => 'Money in, not sorted yet',
      BookAccountKind.uncategorisedSpending => 'Costs, not sorted yet',
      BookAccountKind.fees => 'Fees and charges',
      BookAccountKind.tax => 'Tax paid',
      BookAccountKind.costOfSales => 'Cost of stock sold',
      BookAccountKind.stockLosses => 'Stock spoiled or lost',
      _ => a.kind.name,
    };

/// Profit and loss from [books] for [period], biggest first.
ProfitAndLoss profitAndLoss(
  Books books,
  ReportPeriod period, {
  required Map<int, String> categoryNames,
  required String currency,
}) {
  final from = period.from.startInstant;
  final to = period.to.startInstant;
  final income = <BookAccount, int>{};
  final costs = <BookAccount, int>{};
  for (final e in books.entries) {
    if (e.currency != currency || e.at.isBefore(from) || !e.at.isBefore(to)) {
      continue;
    }
    for (final l in e.lines) {
      switch (l.account.accountClass) {
        case BookAccountClass.income:
          income[l.account] = (income[l.account] ?? 0) - l.amountMinor;
        case BookAccountClass.expense:
          costs[l.account] = (costs[l.account] ?? 0) + l.amountMinor;
        case _:
          break;
      }
    }
  }
  List<PnlLine> lines(Map<BookAccount, int> m) => [
    for (final MapEntry(:key, :value) in m.entries)
      if (value != 0) PnlLine(bookAccountName(key, categoryNames), value),
  ]..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
  return ProfitAndLoss(income: lines(income), costs: lines(costs));
}

/// The balance summary at the end of [period].
BalanceSummary balanceSummary(
  Books books,
  ReportPeriod period, {
  required String currency,
}) {
  final to = period.to.startInstant;
  var money = 0;
  for (final MapEntry(:key, :value)
      in books.trialBalance(currency: currency, to: to).entries) {
    if (key.kind == BookAccountKind.money) money += value;
  }
  return BalanceSummary(
    moneyMinor: money,
    owedToYouMinor: books.balanceOf(
      BookAccount.owedToYou,
      currency: currency,
      to: to,
    ),
    owedToSuppliersMinor: books.balanceOf(
      BookAccount.owedToSuppliers,
      currency: currency,
      to: to,
    ),
    stockMinor: books.balanceOf(BookAccount.stock, currency: currency, to: to),
    paidYourselfMinor: -books.balanceOf(
      BookAccount.ownerPay,
      currency: currency,
      from: period.from.startInstant,
      to: to,
    ),
  );
}

/// One item sold in a period.
class SoldLine {
  const SoldLine({
    required this.name,
    required this.quantityMilli,
    required this.amountMinor,
    required this.costMinor,
    this.itemId,
    this.unit,
    this.service = false,
  });

  final int? itemId;
  final String name;
  final String? unit;
  final int quantityMilli;
  final int amountMinor;

  /// What the stock sold cost; 0 for services.
  final int costMinor;
  final bool service;

  int get profitMinor => amountMinor - costMinor;
}

/// Items by sales, biggest first, adding lines of the same item.
List<SoldLine> bestSellers(Iterable<SoldLine> lines, {int top = 5}) {
  final byItem = <Object, SoldLine>{};
  for (final l in lines) {
    final key = l.itemId ?? l.name;
    final was = byItem[key];
    byItem[key] = was == null
        ? l
        : SoldLine(
            itemId: l.itemId,
            name: was.name,
            unit: was.unit,
            service: was.service,
            quantityMilli: was.quantityMilli + l.quantityMilli,
            amountMinor: was.amountMinor + l.amountMinor,
            costMinor: was.costMinor + l.costMinor,
          );
  }
  final out = byItem.values.where((l) => l.itemId != null).toList()
    ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
  return out.take(top).toList();
}

/// Sales for each weekday in [period], Monday first, filed under
/// [salesCategoryId].
List<int> salesByWeekday(
  Books books,
  ReportPeriod period, {
  required int salesCategoryId,
  required String currency,
}) {
  final sales = BookAccount.category(salesCategoryId, income: true);
  final from = period.from.startInstant;
  final to = period.to.startInstant;
  final out = List.filled(7, 0);
  for (final e in books.entries) {
    if (e.currency != currency || e.at.isBefore(from) || !e.at.isBefore(to)) {
      continue;
    }
    for (final l in e.lines) {
      if (l.account == sales) {
        out[CalendarDate.local(e.at).weekday - 1] -= l.amountMinor;
      }
    }
  }
  return out;
}

/// Sales on each day of [period], first day first, filed under
/// [salesCategoryId].
List<int> salesByDay(
  Books books,
  ReportPeriod period, {
  required int salesCategoryId,
  required String currency,
}) {
  final sales = BookAccount.category(salesCategoryId, income: true);
  final from = period.from.startInstant;
  final to = period.to.startInstant;
  final out = List.filled(period.days < 0 ? 0 : period.days, 0);
  for (final e in books.entries) {
    if (e.currency != currency || e.at.isBefore(from) || !e.at.isBefore(to)) {
      continue;
    }
    final day = period.from.daysUntil(CalendarDate.local(e.at));
    if (day < 0 || day >= out.length) continue;
    for (final l in e.lines) {
      if (l.account == sales) out[day] -= l.amountMinor;
    }
  }
  return out;
}

/// Sales by how people paid in [period].
Map<SalePaymentMethod, int> salesByWay(
  Books books,
  ReportPeriod period, {
  required int salesCategoryId,
  required Map<int, AccountType> accountTypes,
  required String currency,
}) {
  final sales = BookAccount.category(salesCategoryId, income: true);
  final from = period.from.startInstant;
  final to = period.to.startInstant;
  final out = <SalePaymentMethod, int>{};
  for (final e in books.entries) {
    if (e.currency != currency || e.at.isBefore(from) || !e.at.isBefore(to)) {
      continue;
    }
    final sold = -e.lines
        .where((l) => l.account == sales)
        .fold(0, (sum, l) => sum + l.amountMinor);
    if (sold == 0) continue;
    SalePaymentMethod? way;
    for (final l in e.lines) {
      if (l.account == BookAccount.owedToYou) {
        way = SalePaymentMethod.credit;
        break;
      }
      if (l.account.kind == BookAccountKind.money) {
        way = switch (accountTypes[l.account.id]) {
          AccountType.cash => SalePaymentMethod.cash,
          AccountType.mpesa => SalePaymentMethod.mpesa,
          null => null,
          _ => SalePaymentMethod.bank,
        };
        break;
      }
    }
    if (way != null) out[way] = (out[way] ?? 0) + sold;
  }
  return {
    for (final w in SalePaymentMethod.values)
      if ((out[w] ?? 0) != 0) w: out[w]!,
  };
}

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Short, plain sentences about a period, each from the records.
List<String> businessInsights({
  required List<int> byWeekday,
  required ProfitAndLoss pnl,
  required List<SoldLine> sold,
  required int moneyInMinor,
  required int moneyOutMinor,
  required int customersOverTwoWeeks,
  required int owedOverTwoWeeksMinor,
  required int closes,
  required int closesMatched,
  required List<String> runningLow,
  required String Function(int minor) plain,
}) {
  final out = <String>[];
  final total = byWeekday.fold(0, (sum, v) => sum + v);
  if (total > 0) {
    var best = 0;
    for (var i = 1; i < 7; i++) {
      if (byWeekday[i] > byWeekday[best]) best = i;
    }
    final share = (byWeekday[best] * 100 / total).round();
    out.add('${_weekdayNames[best]} is your best day, with $share% of sales.');
  }
  final products = sold.where((s) => !s.service && s.itemId != null);
  final services = sold.where((s) => s.service);
  if (products.isNotEmpty && services.isNotEmpty) {
    final p = products.fold(0, (sum, s) => sum + s.profitMinor);
    final s = services.fold(0, (sum, x) => sum + x.profitMinor);
    out.add('Products made ${plain(p)} profit and services ${plain(s)}.');
  }
  if (moneyInMinor > 0 || moneyOutMinor > 0) {
    final gap = moneyInMinor - moneyOutMinor;
    out.add(
      gap >= 0
          ? 'Money in ${plain(moneyInMinor)} and out ${plain(moneyOutMinor)}, '
                'so you are ${plain(gap)} ahead.'
          : 'Money in ${plain(moneyInMinor)} and out ${plain(moneyOutMinor)}. '
                'Stock bought ahead often does this.',
    );
  }
  if (customersOverTwoWeeks > 0) {
    out.add(
      customersOverTwoWeeks == 1
          ? '1 customer owes ${plain(owedOverTwoWeeksMinor)} for over two '
                'weeks. A reminder often helps.'
          : '$customersOverTwoWeeks customers owe '
                '${plain(owedOverTwoWeeksMinor)} for over two weeks. A '
                'reminder often helps.',
    );
  }
  if (runningLow.isNotEmpty) {
    out.add(
      runningLow.length == 1
          ? '${runningLow.single} is running low.'
          : '${runningLow.length} items are running low: '
                '${runningLow.take(3).join(', ')}.',
    );
  }
  if (closes > 0) {
    out.add('Your drawer matched $closesMatched of the last $closes closes.');
  }
  return out;
}
