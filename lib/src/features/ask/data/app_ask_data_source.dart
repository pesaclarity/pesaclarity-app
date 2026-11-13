import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/ask_repository.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../data/repositories/goals_repository.dart';
import '../../../data/repositories/stock_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/ask/data_source.dart';
import '../../../domain/ask/matcher.dart';
import '../../../domain/ask/periods.dart';
import '../../../domain/ask/understanding.dart';
import '../../../domain/books/business_report.dart';
import '../../../domain/ledger/balances.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../business_insights/application/business_report_providers.dart';
import '../../home/application/safe_to_spend_provider.dart';
import '../../home/application/upcoming_bills_provider.dart';
import '../../lending/application/lending_providers.dart';
import '../../people/application/people_providers.dart';
import '../../spaces/application/spaces_providers.dart';
import '../../subscriptions/application/subscriptions_providers.dart';

/// [AskDataSource] on the open space's database. Every figure comes from
/// the same repositories and providers the app's screens use: safe to spend
/// from Home's provider, bills from Coming up, debts from the debt planner,
/// profit from Business insights.
class AppAskDataSource implements AskDataSource {
  AppAskDataSource(this._ref);

  final Ref _ref;

  AppDatabase get _db => _ref.read(appDatabaseProvider);

  CalendarDate get _today => CalendarDate.local(_ref.read(clockProvider)());

  @override
  Future<List<AskEntity>> entities() async {
    final db = _db;
    final payees = await db.select(db.payees).get();
    final out = <AskEntity>[
      for (final c in await db.select(db.categories).get())
        AskEntity(SlotKind.category, 'c:${c.id}', c.name),
      for (final p in payees)
        AskEntity(SlotKind.payee, 'p:${p.id}', p.displayName),
      for (final a in await db.select(db.accounts).get())
        AskEntity(SlotKind.account, 'a:${a.id}', a.name),
      for (final i in await db.select(db.items).get())
        AskEntity(SlotKind.item, 'i:${i.id}', i.name),
    ];
    // Names printed on messages from people not named as payees yet.
    final t = db.transactions;
    final query = db.selectOnly(t, distinct: true)
      ..addColumns([t.counterpartyName])
      ..where(t.payeeId.isNull() & t.counterpartyName.isNotNull());
    final named = {for (final p in payees) normaliseName(p.displayName)};
    for (final row in await query.get()) {
      final name = row.read(t.counterpartyName);
      if (name == null) continue;
      final key = normaliseName(name);
      if (key.isEmpty || named.contains(key)) continue;
      out.add(AskEntity(SlotKind.payee, 'n:$key', _titleCase(name)));
    }
    return out;
  }

  @override
  Future<List<AskShortcut>> shortcuts() =>
      _ref.read(askRepositoryProvider).shortcuts();

  @override
  Future<List<LedgerEntry>> entries(DateTime from, DateTime to) => _ref
      .read(transactionsRepositoryProvider)
      .ledgerEntries(from: from, to: to);

  @override
  Future<AskSafeToSpend?> safeToSpend() async {
    final safe = await _ref.read(safeToSpendTodayProvider.future);
    if (safe == null) return null;
    return AskSafeToSpend(
      leftTodayMinor: safe.leftTodayMinor,
      overMinor: safe.overTodayMinor,
    );
  }

  @override
  Future<List<AskLine>> billsDue() async => [
    for (final b in await _ref.read(upcomingBillsProvider.future))
      AskLine(b.name, b.amountMinor, date: b.dueDate),
  ];

  @override
  Future<List<AskLine>> subscriptions() async => [
    for (final l in (await _ref.read(
      subscriptionsOverviewProvider.future,
    )).lines)
      AskLine(l.subscription.name, l.monthlyCostMinor, date: l.nextDate),
  ];

  @override
  Future<List<AskLine>> debts() async => [
    for (final d
        in await _ref.read(debtsRepositoryProvider).debts(today: _today))
      if (d.balanceMinor > 0 && d.currency == BaseCurrency.code)
        AskLine(d.lender, d.balanceMinor),
  ];

  @override
  Future<List<AskLine>> lent() async {
    final today = _today;
    return [
      for (final loan in (await _ref.read(lendingOverviewProvider.future)).lent)
        if (loan.status(today) case final s
            when s.amountMinor - s.paidMinor > 0 &&
                loan.currency == BaseCurrency.code)
          AskLine(loan.person, s.amountMinor - s.paidMinor, date: loan.dueDate),
    ];
  }

  @override
  Future<List<AskLine>> owedToMe() async {
    if (!_sells) return const [];
    return [
      for (final c in await _ref.read(customersProvider.future))
        if (c.owedMinor > 0) AskLine(c.name, c.owedMinor, date: c.nextDue),
    ];
  }

  @override
  Future<List<AskLine>> goals() async => [
    for (final g in await _ref.read(goalsRepositoryProvider).goals())
      if (g.currency == BaseCurrency.code)
        AskLine(g.name, g.savedMinor, extraMinor: g.targetMinor),
  ];

  @override
  Future<List<AskLine>> balances() async {
    final accounts = await _ref.read(accountsRepositoryProvider).openings();
    if (accounts.isEmpty) return const [];
    final names = {
      for (final a in await _db.select(_db.accounts).get()) a.id: a.name,
    };
    final start = accounts
        .map((a) => a.openingDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final now = _ref.read(clockProvider)();
    final entries = await this.entries(start, now.add(const Duration(days: 1)));
    return [
      for (final a in accounts)
        if (a.currency == BaseCurrency.code)
          AskLine(names[a.id] ?? 'Account', balanceAt(a, entries, at: now)),
    ];
  }

  @override
  Future<AskLine> sales(AskPeriod period) async {
    final s = _db.sales;
    final total = s.totalMinor.sum();
    final count = s.id.count();
    final row =
        await (_db.selectOnly(s)
              ..addColumns([total, count])
              ..where(
                _inPeriod(s.soldAt, period) &
                    s.currency.equals(BaseCurrency.code),
              ))
            .getSingle();
    return AskLine('Sales', row.read(total) ?? 0, count: row.read(count) ?? 0);
  }

  @override
  Future<List<AskLine>> itemsSold(AskPeriod period) async {
    final l = _db.saleLines;
    final s = _db.sales;
    final total = l.totalMinor.sum();
    final count = l.id.count();
    final rows =
        await (_db.selectOnly(l).join([innerJoin(s, s.id.equalsExp(l.saleId))])
              ..addColumns([l.name, total, count])
              ..where(
                _inPeriod(s.soldAt, period) &
                    s.currency.equals(BaseCurrency.code),
              )
              ..groupBy([l.name])
              ..orderBy([OrderingTerm.desc(total)]))
            .get();
    return [
      for (final r in rows)
        AskLine(r.read(l.name)!, r.read(total) ?? 0, count: r.read(count)),
    ];
  }

  @override
  Future<int?> profit(AskPeriod period) async {
    if (!_sells) return null;
    final pnl = await _ref.read(
      businessProfitProvider(
        ReportPeriod(period.from, period.to, period.label(_today)),
      ).future,
    );
    return pnl.profitMinor;
  }

  @override
  Future<List<AskLine>> lowStock() async => [
    for (final i in await _ref.read(stockRepositoryProvider).items())
      if (i.isLow) AskLine(i.name, 0, count: i.stockMilli),
  ];

  bool get _sells {
    final kind = _ref.read(activeSpaceProvider).kind;
    return kind == SpaceKind.business || kind == SpaceKind.farm;
  }

  static Expression<bool> _inPeriod(
    GeneratedColumn<DateTime> at,
    AskPeriod period,
  ) =>
      at.isBiggerOrEqualValue(period.fromInstant) &
      at.isSmallerThanValue(period.toInstant);

  static String _titleCase(String name) => name
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
