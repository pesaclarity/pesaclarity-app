import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/message_reads_repository.dart';
import 'package:pesaclarity/src/data/repositories/review_inbox_repository.dart';
import 'package:pesaclarity/src/data/repositories/savings_repository.dart';
import 'package:pesaclarity/src/data/repositories/statement_imports_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/ledger/activity_feed.dart';
import 'package:pesaclarity/src/domain/ledger/activity_lines.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_role.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/savings/savings_product.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/sms/application/message_recheck.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/statements/application/statement_importer.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../helpers/fake_sms_source.dart';
import '../../helpers/statement_samples.dart';
import '../../helpers/test_app.dart';

// Synthetic messages in the shape of M-Pesa's: the paybill's name is
// public; the account codes, receipts, amounts and times are invented. No
// sample of money coming back from Chumz exists yet, so it is written in
// the shape of any money received from a business.

final _mpesa = institutionCatalogue.singleWhere((i) => i.id == 'mpesa');

/// A payment to the Nabo Capital paybill for the Chumz account [code].
SmsMessage _paid(
  String receipt,
  String amount,
  String code,
  DateTime at, {
  String fee = '0.00',
}) => SmsMessage(
  sender: 'MPESA',
  body:
      '$receipt Confirmed. Ksh$amount sent to NABO CAPITAL LTD C2B for '
      'account $code on ${_day(at)} at ${_time(at)} New M-PESA balance is '
      'Ksh2,000.00. Transaction cost, Ksh$fee.',
  receivedAt: at.add(const Duration(seconds: 5)),
);

/// Money received from Nabo Capital.
SmsMessage _back(String receipt, String amount, DateTime at) => SmsMessage(
  sender: 'MPESA',
  body:
      '$receipt Confirmed.You have received Ksh$amount from NABO CAPITAL LTD '
      'on ${_day(at)} at ${_time(at)} New M-PESA balance is Ksh3,000.00.',
  receivedAt: at.add(const Duration(seconds: 5)),
);

/// An ordinary payment, to show nothing else changes.
SmsMessage _till(String receipt, DateTime at) => SmsMessage(
  sender: 'MPESA',
  body:
      '$receipt Confirmed. Ksh350.00 paid to EXAMPLE GROCERS. on ${_day(at)} '
      'at ${_time(at)}.New M-PESA balance is Ksh1,650.00. Transaction cost, '
      'Ksh0.00.',
  receivedAt: at.add(const Duration(seconds: 5)),
);

/// [at], a UTC instant, as M-Pesa prints the day in Nairobi.
String _day(DateTime at) {
  final local = at.add(const Duration(hours: 3));
  return '${local.day}/${local.month}/${local.year % 100}';
}

String _time(DateTime at) {
  final local = at.add(const Duration(hours: 3));
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}

/// A UTC instant for a Nairobi wall-clock time.
DateTime _eat(int month, int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, month, day, hour - 3, minute);

final _first = _paid('TKA0000001', '1,000.00', 'CH12345', _eat(8, 5, 9));
final _second = _paid(
  'TKA0000002',
  '1,500.00',
  'CH67890',
  _eat(10, 2, 18, 30),
  fee: '10.00',
);
final _moneyBack = _back('TKB0000003', '1,000.00', _eat(11, 10, 14));
final _groceries = _till('TKC0000004', _eat(11, 12, 13, 45));
final _today = _paid('TKA0000005', '50.00', 'CH12345', _eat(11, 21, 9, 41));

void main() {
  late AppDatabase db;
  late DriftTransactionsRepository transactions;
  late DriftSavingsRepository savings;
  late SmsIngestor ingestor;

  setUp(() {
    db = openTestDatabase();
    transactions = DriftTransactionsRepository(db);
    savings = DriftSavingsRepository(db);
    addTearDown(savings.dispose);
    ingestor = SmsIngestor(
      accounts: DriftAccountsRepository(db),
      transactions: transactions,
      reviewInbox: DriftReviewInboxRepository(
        db,
        clock: () => DateTime.utc(2026, 11, 21),
      ),
      reads: MessageReadsRepository(db),
      parse: (packs, messages) async => parseAll(packs, messages),
    );
  });

  Future<int> mpesa() async => (await (db.select(
    db.accounts,
  )..where((a) => a.institutionId.equals('mpesa'))).getSingle()).id;

  Future<List<TransactionRecord>> rows({int? accountId}) =>
      (db.select(db.transactions)
            ..where(
              (t) => accountId == null
                  ? const Constant(true)
                  : t.accountId.equals(accountId),
            )
            ..orderBy([
              (t) => OrderingTerm.asc(t.occurredAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .get();

  Future<List<LedgerEntry>> entries() => transactions.ledgerEntries(
    from: DateTime.utc(2026),
    to: DateTime.utc(2027),
  );

  Future<LedgerTotals> totals() async => LedgerTotals.of(
    await entries(),
    from: DateTime.utc(2026),
    to: DateTime.utc(2027),
    currency: 'KES',
  );

  Future<LedgerEntry> entryFor(String receipt) async {
    final id = (await rows()).singleWhere((r) => r.receiptNo == receipt).id;
    return (await entries()).singleWhere((e) => e.id == id);
  }

  Future<int> addChumz() async =>
      (await savings.add(chumz, at: _eat(11, 21, 10))).accountId;

  /// What the Chumz account and its entries look like, to compare before
  /// and after something reads the messages again.
  Future<List<(int, int, int?, int?)>> chumzSide(int accountId) async => [
    for (final r in await rows(accountId: accountId))
      (r.id, r.amountMinor, r.transferPairId, r.transferAccountId),
  ];

  test('read before Chumz is added, paying in is spending and money back '
      'is money in', () async {
    await ingestor.ingest([_first, _second, _moneyBack, _groceries], [_mpesa]);

    final stored = await rows();
    expect(stored, hasLength(4));
    final first = stored.first;
    expect(first.kind, TransactionKind.paybill);
    expect(first.counterpartyKind, PayeeIdentifierKind.paybill);
    expect(first.counterpartyValue, 'NABO CAPITAL LTD C2B#CH12345');
    expect(roleOf(await entryFor('TKA0000001')), LedgerRole.spending);
    expect(roleOf(await entryFor('TKA0000002')), LedgerRole.spending);
    expect(roleOf(await entryFor('TKB0000003')), LedgerRole.awaitingPayee);
    expect(stored.every((r) => r.transferPairId == null), isTrue);

    // The question is asked under the newest payment in.
    final prompt = await savings.prompt();
    expect(prompt!.transactionId, stored[1].id);
    expect(prompt.paidTo, 'NABO CAPITAL LTD');
    expect(prompt.code, 'CH67890');
  });

  test('once added, older payments and money back are own transfers and a '
      'new payment links as it arrives', () async {
    await ingestor.ingest([_first, _second, _moneyBack, _groceries], [_mpesa]);
    final chumzId = await addChumz();
    final wallet = await mpesa();

    for (final receipt in ['TKA0000001', 'TKA0000002', 'TKB0000003']) {
      expect(
        roleOf(await entryFor(receipt)),
        LedgerRole.ownTransfer,
        reason: receipt,
      );
    }
    expect(roleOf(await entryFor('TKC0000004')), LedgerRole.spending);

    await ingestor.ingest([_today], [_mpesa]);
    final payment = (await rows(accountId: wallet))
        .singleWhere((r) => r.receiptNo == 'TKA0000005');
    final mirror = (await rows(accountId: chumzId))
        .singleWhere((r) => r.id == payment.transferPairId);
    expect(payment.transferAccountId, chumzId);
    expect(mirror.direction, TransactionDirection.inflow);
    expect(mirror.amountMinor, 5000);
    expect(mirror.transferPairId, payment.id);
    expect(mirror.transferAccountId, wallet);
    expect(mirror.messageHash, isNull);
    expect(roleOf(await entryFor('TKA0000005')), LedgerRole.ownTransfer);

    // Paying in is saved, never spent; the fee is still a fee, and money
    // back is not income.
    final sums = await totals();
    expect(sums.savingMinor, 100000 + 150000 + 5000);
    expect(sums.spendingMinor, 35000);
    expect(sums.feesMinor, 1000);
    expect(sums.incomeMinor, 0);
    expect(sums.awaitingPayeeMinor, 0);
    expect((await savings.account(chumzId))!.balanceMinor, 150000 + 5000);

    // Activity shows each as one line, M-Pesa to Chumz or back, and not
    // as money out this week.
    final all = await entries();
    final feed = buildActivityFeed(all.reversed, all: all);
    final today = feed.first;
    expect(today.date, CalendarDate(2026, 11, 21));
    final line = today.lines.single as OwnTransferLine;
    expect(line.outflow!.id, payment.id);
    expect(line.inflow!.id, mirror.id);
    final back = feed
        .expand((d) => d.lines)
        .whereType<OwnTransferLine>()
        .singleWhere((l) => l.inflow?.accountId == wallet);
    expect(back.outflow!.accountId, chumzId);
    expect(
      feed.expand((d) => d.lines).whereType<OwnTransferLine>(),
      hasLength(4),
    );
    final week = weekInOut(all, today: CalendarDate(2026, 11, 21));
    expect(week.outMinor, 0);
  });

  test('reading the messages again leaves the link as it is', () async {
    await ingestor.ingest([_first, _second, _moneyBack, _groceries], [_mpesa]);
    final chumzId = await addChumz();
    await ingestor.ingest([_today], [_mpesa]);
    final before = await rows();
    final side = await chumzSide(chumzId);

    final again = await ingestor.ingest(
      [_first, _second, _moneyBack, _groceries, _today],
      [_mpesa],
      again: true,
    );
    expect(again.added, 0);
    expect(await rows(), before);
    expect(await chumzSide(chumzId), side);
  });

  test('a recheck keeps the link, and links a payment it puts right', () async {
    await ingestor.ingest([_first, _second, _moneyBack], [_mpesa]);
    final wallet = await mpesa();
    // A payment stored before the reader knew its currency: it cannot be
    // part of a KES savings account until it is put right.
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: wallet,
            occurredAt: _eat(11, 21, 9, 41),
            amountMinor: 5000,
            currency: const Value('USD'),
            direction: TransactionDirection.outflow,
            kind: const Value(TransactionKind.paybill),
            counterpartyKind: const Value(PayeeIdentifierKind.paybill),
            counterpartyValue: const Value('NABO CAPITAL LTD C2B#CH12345'),
            counterpartyName: const Value('NABO CAPITAL LTD C2B'),
            receiptNo: const Value('TKA0000005'),
            source: TransactionSource.sms,
            messageHash: Value(hashMessageBody(_today.body)),
          ),
        );
    final chumzId = await addChumz();
    expect((await savings.account(chumzId))!.balanceMinor, 150000);
    final side = await chumzSide(chumzId);

    final source = FakeSmsSource(inbox: [_first, _second, _moneyBack, _today]);
    addTearDown(source.close);
    final notice = await MessageRecheck(
      db: db,
      source: source,
      accounts: DriftAccountsRepository(db),
      settings: DriftAppSettingsRepository(db),
      parse: (packs, messages) async => parseAll(packs, messages),
    ).recheck([_mpesa]);

    expect(notice!.count, 1);
    expect(notice.currency, 'KES');
    final payment = (await rows()).singleWhere(
      (r) => r.receiptNo == 'TKA0000005',
    );
    expect(payment.currency, 'KES');
    expect(payment.transferAccountId, chumzId);
    // The others are as they were, with their entries.
    expect((await chumzSide(chumzId)).take(side.length), side);
    expect((await savings.account(chumzId))!.balanceMinor, 150000 + 5000);
  });

  test('a statement of the same payments adds no second payment or entry, '
      'and links one only it shows', () async {
    await ingestor.ingest([_first, _second], [_mpesa]);
    final chumzId = await addChumz();
    final importer = StatementImporter(
      extractor: FakePdfTextExtractor({
        'august-october': mpesaStatementPages(
          period: '01 Aug 2026 - 31 Oct 2026',
          rows: const [
            (
              receipt: 'TKA0000001',
              time: '2026-08-05 09:00:00',
              details:
                  'Pay Bill Online to 999999 - NABO CAPITAL LTD Acc. CH12345',
              amount: -100000,
            ),
            (
              receipt: 'TKA0000006',
              time: '2026-09-12 08:15:00',
              details:
                  'Pay Bill Online to 999999 - NABO CAPITAL LTD Acc. CH12345',
              amount: -200000,
            ),
            (
              receipt: 'TKA0000002',
              time: '2026-10-02 18:30:00',
              details:
                  'Pay Bill Online to 999999 - NABO CAPITAL LTD Acc. CH67890',
              amount: -150000,
            ),
            (
              receipt: 'TKA0000002',
              time: '2026-10-02 18:30:00',
              details: 'Pay Bill Charge',
              amount: -1000,
            ),
          ],
        ),
      }),
      read: (pages) async => readStatement(pages),
      accounts: DriftAccountsRepository(db),
      transactions: transactions,
      imports: DriftStatementImportsRepository(db),
      institutions: institutionCatalogue,
      now: () => DateTime.utc(2026, 11, 21, 9),
    );

    final outcome = await importer.importPdf(fakePdf('august-october'));
    final summary = (outcome as StatementImported).summary;
    expect(summary.addedCount, 1);
    expect(summary.duplicateCount, 2);

    final wallet = await rows(accountId: await mpesa());
    expect(wallet, hasLength(3));
    expect(wallet.every((r) => r.transferAccountId == chumzId), isTrue);
    final mirrors = await rows(accountId: chumzId);
    expect(mirrors, hasLength(3));
    expect(
      {for (final m in mirrors) m.transferPairId},
      {for (final w in wallet) w.id},
    );
    final account = (await savings.account(chumzId))!;
    expect(account.balanceMinor, 100000 + 200000 + 150000);
    expect(
      account.pockets.singleWhere((p) => p.code == 'CH12345').paidInMinor,
      300000,
    );
    // The account opens with its first payment.
    final opened = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(chumzId))).getSingle();
    expect(opened.openingDate.isAtSameMomentAs(_eat(8, 5, 9)), isTrue);
  });

  test('money back after Chumz is added is a transfer from Chumz', () async {
    await ingestor.ingest([_first], [_mpesa]);
    final chumzId = await addChumz();
    await ingestor.ingest([_moneyBack], [_mpesa]);

    final back = (await rows()).singleWhere((r) => r.receiptNo == 'TKB0000003');
    expect(back.transferAccountId, chumzId);
    final mirror = (await rows(accountId: chumzId))
        .singleWhere((r) => r.id == back.transferPairId);
    expect(mirror.direction, TransactionDirection.outflow);
    expect(mirror.amountMinor, 100000);
    expect(roleOf(await entryFor('TKB0000003')), LedgerRole.ownTransfer);
    expect((await totals()).incomeMinor, 0);
    // With one goal, the money came out of it.
    final account = (await savings.account(chumzId))!;
    expect(account.unassigned, isEmpty);
    expect(account.pockets.single.takenOutMinor, 100000);
    expect(account.balanceMinor, 0);
  });

  test('money from someone else is left as it is', () async {
    await ingestor.ingest([_first], [_mpesa]);
    await addChumz();
    await ingestor.ingest(
      [
        SmsMessage(
          sender: 'MPESA',
          body:
              'TKD0000007 Confirmed.You have received Ksh500.00 from JANE DOE '
              '0700000000 on 15/11/26 at 8:00 AM New M-PESA balance is '
              'Ksh3,500.00.',
          receivedAt: _eat(11, 15, 8),
        ),
      ],
      [_mpesa],
    );
    final row = (await rows()).singleWhere((r) => r.receiptNo == 'TKD0000007');
    expect(row.transferPairId, isNull);
    expect(row.transferAccountId, isNull);
    expect(roleOf(await entryFor('TKD0000007')), LedgerRole.awaitingPayee);
  });
}
