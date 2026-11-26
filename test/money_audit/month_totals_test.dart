import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/review_inbox_repository.dart';
import 'package:pesaclarity/src/data/repositories/statement_imports_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/debts/fuliza_tracker.dart';
import 'package:pesaclarity/src/domain/insights/leakage.dart';
import 'package:pesaclarity/src/domain/insights/spending_charts.dart';
import 'package:pesaclarity/src/domain/ledger/activity_feed.dart';
import 'package:pesaclarity/src/domain/ledger/fuliza.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_role.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/statements/application/statement_importer.dart';

import '../helpers/sms_samples.dart';
import '../helpers/statement_samples.dart';
import '../helpers/test_app.dart';
import 'sms_month.dart';

int _kes(int shillings, [int cents = 0]) => shillings * 100 + cents;

/// A made-up November of M-Pesa, KCB and Airtel Money messages, read end to
/// end, and every money total that reads the ledger checked against the sum
/// worked out by hand.
void main() {
  late AppDatabase db;
  late SmsIngestor ingestor;
  late DriftTransactionsRepository transactions;
  final institutions = [
    for (final id in ['mpesa', 'kcb', 'airtel_money'])
      institutionCatalogue.singleWhere((i) => i.id == id),
  ];
  // November in Nairobi.
  final from = DateTime.utc(2026, 10, 31, 21);
  final to = DateTime.utc(2026, 11, 30, 21);

  setUp(() {
    db = openTestDatabase();
    transactions = DriftTransactionsRepository(db);
    ingestor = SmsIngestor(
      accounts: DriftAccountsRepository(db),
      transactions: transactions,
      reviewInbox: DriftReviewInboxRepository(
        db,
        clock: () => DateTime.utc(2026, 11, 20),
      ),
    );
  });
  tearDown(() => db.close());

  Future<List<LedgerEntry>> entries() =>
      transactions.ledgerEntries(from: DateTime.utc(2026), to: to);

  // By hand: the grocer 350, Mary 1,500, power 1,200, airtime 100 and 50
  // for another number, Peter 300 given back, and the KCB debit 2,000.
  // Cash out goes into Cash in hand: never spending.
  final spending = _kes(350 + 1500 + 1200 + 100 + 50 + 2000);
  // Transaction costs 30 (to KCB), 15, 15, 29 (agent), 15 (to Airtel) and
  // Fuliza's access fee 1.50, once.
  final fees = _kes(30 + 15 + 15 + 29 + 15, 50) + _kes(1);
  // KCB to M-Pesa 10,000, M-Pesa to KCB 3,000, M-Shwari 500, cash out
  // 1,000 into Cash in hand, cash in 2,000 from it, Airtel 100.
  final own = _kes(10000 + 3000 + 500 + 1000 + 2000 + 100);

  group('a month of messages', () {
    test('income, spending, fees and own transfers', () async {
      await ingestor.ingest(month(), institutions);
      final t = LedgerTotals.of(await entries(), from: from, to: to);
      expect(t.incomeMinor, _kes(50000), reason: 'only the salary');
      expect(t.moneyInMinor, _kes(50000), reason: 'cash put in is no income');
      expect(t.spendingMinor, spending);
      expect(t.feesMinor, fees);
      expect(t.borrowingMinor, _kes(150), reason: 'Fuliza is borrowed');
      expect(
        t.debtRepaymentMinor,
        _kes(5000) + _kes(150),
        reason: 'the loan and what was drawn, never the access fee again',
      );
      expect(t.ownTransferMinor, own);
      expect(t.awaitingPayeeMinor, 0);
    });

    test(
      'with no cash account, the first cash out makes Cash in hand',
      () async {
        await ingestor.ingest([withdraw(), deposit()], institutions);
        final cash = await (db.select(
          db.accounts,
        )..where((a) => a.type.equalsValue(AccountType.cash))).getSingle();
        expect(cash.name, 'Cash in hand');
        final list = await entries();
        expect(list, hasLength(4), reason: 'each with its side on cash');
        expect(list.map(roleOf).toSet(), {LedgerRole.ownTransfer});
        expect(
          list.where((e) => e.accountId == cash.id).map((e) => e.signedMinor),
          [_kes(1000), -_kes(2000)],
          reason: 'more put in than taken out: cash is short, to be set right',
        );
        final t = LedgerTotals.of(list, from: from, to: to);
        expect(t.spendingMinor, 0);
        expect(t.moneyInMinor, 0);
        expect(t.incomeMinor, 0);
        expect(t.feesMinor, _kes(29), reason: 'the cost still counts');
      },
    );

    test('with a cash account, cash out and in move to and from it', () async {
      final cash = await DriftAccountsRepository(db)
          .cashAccount(name: 'Cash', openingDate: DateTime.utc(2026, 10));
      await ingestor.ingest([withdraw(), deposit()], institutions);
      final list = await entries();
      expect(list, hasLength(4), reason: 'each with its side on cash');
      expect(list.map(roleOf).toSet(), {LedgerRole.ownTransfer});
      expect(list.where((e) => e.accountId == cash).map((e) => e.signedMinor), [
        _kes(1000),
        -_kes(2000),
      ]);
      final t = LedgerTotals.of(list, from: from, to: to);
      expect(t.spendingMinor, 0);
      expect(t.moneyInMinor, 0);
      expect(t.feesMinor, _kes(29));
      // Read again: no second side on cash.
      await ingestor.ingest([withdraw(), deposit()], institutions);
      expect(await entries(), hasLength(4));
    });

    test('Fuliza: the access fee once, wherever fees are read', () async {
      await ingestor.ingest(fuliza(), institutions);
      final list = await entries();
      final t = LedgerTotals.of(list, from: from, to: to);
      expect(t.incomeMinor, 0);
      expect(t.moneyInMinor, 0);
      expect(t.spendingMinor, 0);
      expect(t.feesMinor, _kes(1, 50));
      expect(t.borrowingMinor, _kes(150));
      expect(t.debtRepaymentMinor, _kes(150));
      final ledger = FulizaLedger.of(list);
      expect(ledger.outstandingMinor, 0);
      final month = ledger.month(list, YearMonth(2026, 11));
      expect(month.feesMinor, _kes(1, 50));
      final leakage = LeakageBreakdown.of(list, from: from, to: to);
      expect(leakage.feesMinor + leakage.fulizaMinor, _kes(1, 50));
      final chart = SpendingChart.of(
        list,
        period: ChartPeriod.month,
        today: CalendarDate(2026, 11, 20),
      );
      expect(chart.totalMinor, _kes(1, 50));
      expect(FulizaTracker.of(list).outstandingMinor, 0);
    });

    test('a reversal cancels its payment, both ways', () async {
      await ingestor.ingest(reversedSend(), institutions);
      final t = LedgerTotals.of(await entries(), from: from, to: to);
      expect(t.spendingMinor, 0);
      expect(t.incomeMinor, 0);
      expect(t.moneyInMinor, 0);
    });

    test('a declined card payment is ignored', () async {
      await ingestor.ingest([declinedCard()], institutions);
      expect(await entries(), isEmpty);
    });

    test('reading the messages again counts each once', () async {
      await ingestor.ingest(month(), institutions);
      final once = LedgerTotals.of(await entries(), from: from, to: to);
      final again = await ingestor.ingest(month(), institutions);
      expect(again.added, 0);
      final twice = LedgerTotals.of(await entries(), from: from, to: to);
      expect(twice.spendingMinor, once.spendingMinor);
      expect(twice.incomeMinor, once.incomeMinor);
      expect(twice.feesMinor, once.feesMinor);
      expect(twice.ownTransferMinor, once.ownTransferMinor);
    });

    test('Insights, the week and the chart agree with the totals', () async {
      await ingestor.ingest(month(), institutions);
      final list = await entries();
      final t = LedgerTotals.of(list, from: from, to: to);
      final chart = SpendingChart.of(
        list,
        period: ChartPeriod.month,
        today: CalendarDate(2026, 11, 30),
      );
      expect(chart.totalMinor, t.spendingMinor + t.feesMinor);
      // The week of the 16th: the loan, the KCB debit and Airtel.
      final week = weekInOut(list, today: CalendarDate(2026, 11, 22));
      expect(week.inMinor, 0);
      expect(week.outMinor, _kes(2000) + _kes(15));
    });
  });

  test('a statement after the messages counts each once', () async {
    Future<LedgerTotals> totals(AppDatabase db) async => LedgerTotals.of(
      await DriftTransactionsRepository(db)
          .ledgerEntries(from: DateTime.utc(2026), to: DateTime.utc(2027)),
      from: DateTime.utc(2026),
      to: DateTime.utc(2027),
    );
    StatementImporter importerFor(AppDatabase db) => StatementImporter(
      extractor: FakePdfTextExtractor({'october': mpesaStatementPages()}),
      read: (pages) async => readStatement(pages),
      accounts: DriftAccountsRepository(db),
      transactions: DriftTransactionsRepository(db),
      imports: DriftStatementImportsRepository(db),
      institutions: institutionCatalogue,
      now: () => DateTime.utc(2026, 11, 2, 9),
    );
    await SmsIngestor(
      accounts: DriftAccountsRepository(db),
      transactions: transactions,
      reviewInbox: DriftReviewInboxRepository(db),
      parse: (packs, messages) async => parseAll(packs, messages),
    ).ingest([mpesaSent(), mpesaTill()], institutionCatalogue);
    await importerFor(db).importPdf(fakePdf('october'));
    final both = await totals(db);

    final alone = openTestDatabase();
    addTearDown(alone.close);
    await importerFor(alone).importPdf(fakePdf('october'));
    final statement = await totals(alone);
    expect(both.spendingMinor, statement.spendingMinor);
    expect(both.incomeMinor, statement.incomeMinor);
    expect(both.feesMinor, statement.feesMinor);
  });
}
