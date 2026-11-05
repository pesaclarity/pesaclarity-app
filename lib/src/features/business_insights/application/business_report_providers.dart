import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/day_closes_repository.dart';
import '../../../data/repositories/sales_repository.dart';
import '../../../data/repositories/stock_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/books/book_account.dart';
import '../../../domain/books/business_report.dart';
import '../../../domain/books/cash_book.dart';
import '../../../domain/enums.dart';
import '../../../domain/people/people.dart';
import '../../../domain/stock/stock.dart';
import '../../../domain/time/calendar.dart';
import '../../books/application/books_providers.dart';
import '../../payees/application/payee_providers.dart';
import '../../people/application/people_providers.dart';
import '../../stock/application/stock_providers.dart';

/// Everything a business report shows for one period.
class BusinessReport {
  const BusinessReport({
    required this.period,
    required this.pnl,
    required this.previousProfitMinor,
    required this.previousLabel,
    required this.items,
    required this.byWay,
    required this.bestSellers,
    required this.byWeekday,
    required this.balance,
    required this.insights,
    required this.customers,
    required this.suppliers,
    this.previousPnl = const ProfitAndLoss(income: [], costs: []),
    this.byDay = const [],
  });

  final ReportPeriod period;
  final ProfitAndLoss pnl;
  final int previousProfitMinor;

  /// Profit and loss for the period before, line by line.
  final ProfitAndLoss previousPnl;

  /// Sales on each day of the period, first day first.
  final List<int> byDay;

  /// What the period is compared with, such as `October`.
  final String previousLabel;

  /// Everything the business sells, as it stands today.
  final List<Item> items;
  final Map<SalePaymentMethod, int> byWay;
  final List<SoldLine> bestSellers;
  final List<int> byWeekday;
  final BalanceSummary balance;
  final List<String> insights;
  final List<CustomerAccount> customers;
  final List<SupplierAccount> suppliers;

  int get salesMinor => byWay.values.fold(0, (sum, v) => sum + v);
}

/// Profit and loss alone for [period], lighter than the whole report.
final businessProfitProvider =
    FutureProvider.family<ProfitAndLoss, ReportPeriod>((ref, period) async {
      final books = await ref.watch(booksProvider.future);
      final categories = await ref.watch(categoriesProvider.future);
      return profitAndLoss(
        books,
        period,
        categoryNames: {for (final c in categories) c.id: c.name},
        currency: BaseCurrency.code,
      );
    });

final businessReportProvider =
    FutureProvider.family<BusinessReport, ReportPeriod>((ref, period) async {
      final books = await ref.watch(booksProvider.future);
      final categories = await ref.watch(categoriesProvider.future);
      final names = {for (final c in categories) c.id: c.name};
      final salesId = await ref
          .watch(salesRepositoryProvider)
          .salesCategoryId();
      final accounts = await ref.watch(accountsRepositoryProvider).openings();
      final types = {for (final a in accounts) a.id: a.type};
      final currency = BaseCurrency.code;
      final pnl = profitAndLoss(
        books,
        period,
        categoryNames: names,
        currency: currency,
      );
      final compared = comparisonFor(period);
      final previous = profitAndLoss(
        books,
        compared,
        categoryNames: names,
        currency: currency,
      );
      final sold = await ref
          .watch(stockRepositoryProvider)
          .soldLines(
            from: period.from.startInstant,
            to: period.to.startInstant,
          );
      final byWeekday = salesByWeekday(
        books,
        period,
        salesCategoryId: salesId,
        currency: currency,
      );
      final customers = await ref.watch(customersProvider.future);
      final suppliers = await ref.watch(suppliersProvider.future);
      final items = await ref.watch(itemsProvider.future);
      final today = CalendarDate.local(ref.watch(clockProvider)());
      final closes = await ref
          .watch(dayClosesRepositoryProvider)
          .since(today.addDays(-6));

      var moneyIn = 0;
      var moneyOut = 0;
      final from = period.from.startInstant;
      final to = period.to.startInstant;
      for (final e in books.entries) {
        if (e.currency != currency ||
            e.at.isBefore(from) ||
            !e.at.isBefore(to)) {
          continue;
        }
        // Moves between the business's own accounts are neither.
        if (e.lines.every(
          (l) =>
              l.account.kind == BookAccountKind.money ||
              l.account == BookAccount.ownTransfers ||
              l.account == BookAccount.fees,
        )) {
          continue;
        }
        for (final l in e.lines) {
          if (l.account.kind != BookAccountKind.money) continue;
          if (l.amountMinor > 0) {
            moneyIn += l.amountMinor;
          } else {
            moneyOut -= l.amountMinor;
          }
        }
      }
      final over = [
        for (final c in customers)
          if (c.overTwoWeeksMinor > 0) c,
      ];
      String plain(int minor) => formatMoney(Money(minor), withCurrency: false);

      return BusinessReport(
        period: period,
        pnl: pnl,
        previousProfitMinor: previous.profitMinor,
        previousPnl: previous,
        previousLabel: compared.label,
        byDay: salesByDay(
          books,
          period,
          salesCategoryId: salesId,
          currency: currency,
        ),
        items: items,
        byWay: salesByWay(
          books,
          period,
          salesCategoryId: salesId,
          accountTypes: types,
          currency: currency,
        ),
        bestSellers: bestSellers(sold),
        byWeekday: byWeekday,
        balance: balanceSummary(books, period, currency: currency),
        customers: [
          for (final c in customers)
            if (c.owedMinor > 0) c,
        ],
        suppliers: suppliers,
        insights: businessInsights(
          byWeekday: byWeekday,
          pnl: pnl,
          sold: sold,
          moneyInMinor: moneyIn,
          moneyOutMinor: moneyOut,
          customersOverTwoWeeks: over.length,
          owedOverTwoWeeksMinor: over.fold(
            0,
            (sum, c) => sum + c.overTwoWeeksMinor,
          ),
          closes: closes.length,
          closesMatched: closes.where((c) => c.differenceMinor == 0).length,
          runningLow: [
            for (final i in items)
              if (i.isLow) i.name,
          ],
          plain: plain,
        ),
      );
    });

/// The cash book for [period]: balances at its end and every day in it.
final reportCashBookProvider = FutureProvider.family<CashBook, ReportPeriod>((
  ref,
  period,
) async {
  ref.watch(ledgerChangesProvider);
  final to = period.to.startInstant;
  final accounts = await ref.watch(accountsRepositoryProvider).openings();
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(from: DateTime.utc(1970), to: to);
  return CashBook.of(
    entries,
    accounts: accounts,
    to: to,
    from: period.from,
    currency: BaseCurrency.code,
  );
});
