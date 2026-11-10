import '../books/book_account.dart';
import '../books/books.dart';
import '../enums.dart';
import '../time/business_day.dart';
import '../time/calendar.dart';

/// One day's sales, by how people paid.
class SalesDay {
  const SalesDay({required this.date, required this.byWay});

  final CalendarDate date;

  /// Sales by how they were paid, in [SalePaymentMethod] order, only ways
  /// that had sales.
  final Map<SalePaymentMethod, int> byWay;

  int get totalMinor => byWay.values.fold(0, (sum, v) => sum + v);
}

/// Sales on [date] from [books]: everything filed under [salesCategoryId],
/// by where the money went (cash, M-Pesa, bank) or credit for what a
/// customer owes. Money sent back under sales takes from the way it went.
/// The day ends as [business] says.
SalesDay salesOn(
  Books books,
  CalendarDate date, {
  required int salesCategoryId,
  required Map<int, AccountType> accountTypes,
  required String currency,
  BusinessDay business = BusinessDay.midnight,
}) {
  final sales = BookAccount.category(salesCategoryId, income: true);
  final from = business.startOf(date);
  final to = business.endOf(date);
  final byWay = <SalePaymentMethod, int>{};
  for (final e in books.entries) {
    if (e.currency != currency || e.at.isBefore(from) || !e.at.isBefore(to)) {
      continue;
    }
    final sold = -e.lines
        .where((l) => l.account == sales)
        .fold(0, (sum, l) => sum + l.amountMinor);
    if (sold == 0) continue;
    final way = _wayOf(e, sales, accountTypes);
    if (way == null) continue;
    byWay[way] = (byWay[way] ?? 0) + sold;
  }
  return SalesDay(
    date: date,
    byWay: {
      for (final w in SalePaymentMethod.values)
        if ((byWay[w] ?? 0) != 0) w: byWay[w]!,
    },
  );
}

SalePaymentMethod? _wayOf(
  JournalEntry e,
  BookAccount sales,
  Map<int, AccountType> accountTypes,
) {
  for (final l in e.lines) {
    if (l.account == BookAccount.owedToYou) return SalePaymentMethod.credit;
    if (l.account.kind == BookAccountKind.money) {
      return switch (accountTypes[l.account.id]) {
        AccountType.cash => SalePaymentMethod.cash,
        AccountType.mpesa => SalePaymentMethod.mpesa,
        AccountType.bank ||
        AccountType.sacco ||
        AccountType.moneyMarket => SalePaymentMethod.bank,
        null => null,
      };
    }
  }
  return null;
}

/// How many earlier same weekdays make "a usual" day.
const usualDayWeeks = 4;

/// What a usual [date] weekday sells: the average of the [usualDayWeeks]
/// same weekdays before it that had sales. Null with fewer than two such
/// days, which is too few to say.
int? usualSalesFor(
  Books books,
  CalendarDate date, {
  required int salesCategoryId,
  required Map<int, AccountType> accountTypes,
  required String currency,
  BusinessDay business = BusinessDay.midnight,
}) {
  final totals = [
    for (var week = 1; week <= usualDayWeeks; week++)
      salesOn(
        books,
        date.addDays(-7 * week),
        salesCategoryId: salesCategoryId,
        accountTypes: accountTypes,
        currency: currency,
        business: business,
      ).totalMinor,
  ].where((t) => t > 0).toList();
  if (totals.length < 2) return null;
  return totals.fold(0, (sum, t) => sum + t) ~/ totals.length;
}
