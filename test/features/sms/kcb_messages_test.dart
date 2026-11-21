import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/debts_repository.dart';
import 'package:pesaclarity/src/data/repositories/message_reads_repository.dart';
import 'package:pesaclarity/src/data/repositories/review_inbox_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_role.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../helpers/test_app.dart';

// Synthetic messages in the shapes of KCB's and M-Pesa's: invented names,
// account numbers, references, amounts and times.

Institution _institution(String id) =>
    institutionCatalogue.singleWhere((i) => i.id == id);

final _kcb = [_institution('kcb')];
final _kcbAndMpesa = [_institution('kcb'), _institution('mpesa')];

SmsMessage _kcbSms(String body, DateTime at) =>
    SmsMessage(sender: 'KCB', body: body, receivedAt: at);

/// KCB confirming an M-Pesa payment to its paybill for the KCB account.
SmsMessage _paybillConfirmed({String time = '07:45 PM'}) => _kcbSms(
  'Ksh 12000.00 sent to KCB Pay Bill 522522 for account 123***7890 JANE '
  'AKINYI DOE has been received on 05/11/2026 at $time. M-PESA ref '
  'TJA0000020. To reverse this transaction, SMS this message to 16120',
  DateTime.utc(2026, 11, 5, 16, 45, 20),
);

/// M-Pesa's own message for the same payment.
SmsMessage _mpesaPaybill() => SmsMessage(
  sender: 'MPESA',
  body:
      'TJA0000020 Confirmed. Ksh12,000.00 sent to KCB Money Transfer for '
      'account 1234567890 on 5/11/26 at 7:45 PM New M-PESA balance is '
      'Ksh3,000.00. Transaction cost, Ksh50.00.',
  receivedAt: DateTime.utc(2026, 11, 5, 16, 45, 10),
);

/// KCB's credit or debit on the full account number, through [channel].
SmsMessage _movement(
  String way,
  String amount,
  String channel,
  String time, {
  String date = '05 NOV 2026',
}) => _kcbSms(
  'Dear Customer, your acc 1234567890 has been $way KES $amount $channel at '
  'KCB DATA PROCESSING CENTRE at $time on $date. For any queries call KCB '
  'on  +254700000000',
  DateTime.utc(2026, 11, 5, 17),
);

SmsMessage _pesalink({
  String ref = '0001000720261106101500abcd1234',
  String time = '10:15:00 AM',
}) => _kcbSms(
  '$ref Completed. Your SEND TO PESALINK request of KES 8,000.00 from '
  '123****890 to 555****321 - JANE AKINYI DOE at 2026-11-06 $time has been '
  'processed successfully. Transaction cost KES 15.00  Incl. Tax Amount KES '
  '2.00. Pata extra cash with a flexible Mobile Loan of up to KES 100K.',
  DateTime.utc(2026, 11, 6, 7, 20),
);

SmsMessage _loanRepaid(String amount, String left, DateTime at) => _kcbSms(
  'Dear JANE AKINYI DOE, KES $amount was debited from your KCB account to '
  'repay your KCB Salary Advance 100000001. The loan has been partially '
  'paid. Your loan balance is KES $left, next instalment is due on '
  '15/12/2026. Pay the loan to borrow again.',
  at,
);

void main() {
  late AppDatabase db;
  late SmsIngestor ingestor;
  late DriftTransactionsRepository transactionsRepo;

  setUp(() {
    db = openTestDatabase();
    transactionsRepo = DriftTransactionsRepository(db);
    ingestor = SmsIngestor(
      accounts: DriftAccountsRepository(db),
      transactions: transactionsRepo,
      reviewInbox: DriftReviewInboxRepository(
        db,
        clock: () => DateTime.utc(2026, 11, 7),
      ),
    );
  });

  Future<List<TransactionRecord>> rows() => (db.select(
    db.transactions,
  )..orderBy([(t) => OrderingTerm.asc(t.occurredAt)])).get();

  Future<Account> account(String institution) => (db.select(
    db.accounts,
  )..where((a) => a.institutionId.equals(institution))).getSingle();

  group('M-Pesa to KCB paybill', () {
    test('KCB confirmation and KCB credit are one own transfer', () async {
      await ingestor.ingest([
        _paybillConfirmed(),
        _movement('credited', '12,000.00', 'Mobi', '19:45:30'),
      ], _kcb);

      final mpesa = await account('mpesa');
      final kcb = await account('kcb');
      expect(mpesa.type, AccountType.mpesa);
      expect(kcb.reference, '1234567890');
      final [out, into] = await rows();
      expect(out.accountId, mpesa.id);
      expect(out.kind, TransactionKind.paybill);
      expect(out.direction, TransactionDirection.outflow);
      expect(out.receiptNo, 'TJA0000020');
      expect(out.counterpartyName, 'KCB');
      expect(into.accountId, kcb.id);
      expect(into.direction, TransactionDirection.inflow);
      expect(out.transferPairId, into.id);
      expect(into.transferPairId, out.id);
    });

    test('the masked account pairs with the full one an hour apart', () async {
      await ingestor.ingest([
        _movement('credited', '12,000.00', 'Mobi', '20:50:00'),
      ], _kcb);
      await ingestor.ingest([_paybillConfirmed()], _kcb);

      final [out, into] = await rows();
      expect(out.transferPairId, into.id);
      // Named by the account number it went to.
      expect(out.transferAccountId, (await account('kcb')).id);
    });

    for (final mpesaFirst in [true, false]) {
      test("M-Pesa's own message and KCB's are one payment "
          '(${mpesaFirst ? 'M-Pesa' : 'KCB'} first)', () async {
        final messages = [_mpesaPaybill(), _paybillConfirmed()];
        for (final m in mpesaFirst ? messages : messages.reversed) {
          await ingestor.ingest([m], _kcbAndMpesa);
        }
        final [only] = await rows();
        expect(only.receiptNo, 'TJA0000020');
        expect(only.amountMinor, 1200000);
        // M-Pesa's balance and fee are kept, whichever came first.
        expect(only.balanceAfterMinor, 300000);
        expect(only.feeMinor, 5000);
      });
    }

    test('a minute apart they are still one, by the receipt', () async {
      await ingestor.ingest([
        _paybillConfirmed(time: '07:46 PM'),
        _mpesaPaybill(),
      ], _kcbAndMpesa);
      expect(await rows(), hasLength(1));
    });
  });

  test(
    "money from someone else's KCB account is not an own transfer",
    () async {
      await ingestor.ingest([
        _movement(
          'debited',
          '2,500.00',
          'Mobi',
          '15:15:00',
          date: '07 NOV 2026',
        ),
        _kcbSms(
          'KCB0000000000021 Confirmed.  KES 2,500.00 received from MARY WAMBUI '
          'DOE - 987****654 on 2026-11-07 03:15:20 PM via KCB.',
          DateTime.utc(2026, 11, 7, 12, 16),
        ),
      ], _kcb);

      final mpesa = await account('mpesa');
      final received = (await rows()).singleWhere(
        (r) => r.accountId == mpesa.id,
      );
      expect(received.kind, TransactionKind.received);
      expect(received.direction, TransactionDirection.inflow);
      expect(received.counterpartyName, 'MARY WAMBUI DOE');
      expect(received.counterpartyKind, PayeeIdentifierKind.account);
      expect(received.counterpartyValue, '987****654');
      // Its number is not one of the person's accounts: it stays money in.
      expect(received.transferAccountId, isNull);
      final entries = await transactionsRepo.ledgerEntries(
        from: DateTime.utc(2026, 11),
        to: DateTime.utc(2026, 12),
      );
      final entry = entries.singleWhere((e) => e.id == received.id);
      expect(roleOf(entry), LedgerRole.awaitingPayee);
    },
  );

  group('PesaLink', () {
    final debit = _movement(
      'debited',
      '8,000.00',
      'Pesalink Outgoing',
      '10:12:30',
      date: '06 NOV 2026',
    );

    for (final alertFirst in [true, false]) {
      test('the account debit and the completion are one transfer '
          '(${alertFirst ? 'debit' : 'completion'} first)', () async {
        final messages = [debit, _pesalink()];
        for (final m in alertFirst ? messages : messages.reversed) {
          await ingestor.ingest([m], _kcb);
        }
        final [only] = await rows();
        expect(only.receiptNo, '0001000720261106101500abcd1234');
        expect(only.amountMinor, 800000);
        expect(only.feeMinor, 1500);
        expect(only.counterpartyName, 'JANE AKINYI DOE');
        expect(only.twinMessageHash, isNotNull);
        // The full number the debit printed stays the account's.
        expect((await account('kcb')).reference, '1234567890');
      });
    }

    test(
      'a credit just before is income, kept apart from the transfer',
      () async {
        await ingestor.ingest([
          _movement(
            'credited',
            '8,940.00',
            'Direct Credits',
            '10:08:05',
            date: '06 NOV 2026',
          ),
          debit,
          _pesalink(),
        ], _kcb);

        final [income, out] = await rows();
        expect(income.direction, TransactionDirection.inflow);
        expect(income.amountMinor, 894000);
        expect(income.counterpartyName, 'Direct Credits');
        expect(income.transferPairId, isNull);
        expect(out.direction, TransactionDirection.outflow);
        expect(out.amountMinor, 800000);
        expect(out.receiptNo, isNotNull);
      },
    );

    test('two transfers of the same amount stay two', () async {
      await ingestor.ingest([
        debit,
        _pesalink(),
        _pesalink(ref: '0001000720261106101900efgh5678', time: '10:19:00 AM'),
      ], _kcb);
      expect(await rows(), hasLength(2));
    });

    test('two plain debits of the same amount stay two', () async {
      await ingestor.ingest([
        debit,
        _movement(
          'debited',
          '8,000.00',
          'Pesalink Outgoing',
          '10:16:45',
          date: '06 NOV 2026',
        ),
      ], _kcb);
      expect(await rows(), hasLength(2));
    });

    test('to a Loop account the person has is an own transfer', () async {
      final loop = await DriftAccountsRepository(db).accountForInstitution(
        'loop',
        name: 'Loop',
        type: AccountType.bank,
        openingDate: DateTime.utc(2026, 10),
        currency: 'KES',
        reference: '5550000321',
      );
      await ingestor.ingest([_pesalink()], _kcb);
      final [out] = await rows();
      expect(out.transferAccountId, loop);
      final entries = await transactionsRepo.ledgerEntries(
        from: DateTime.utc(2026, 11),
        to: DateTime.utc(2026, 12),
      );
      expect(roleOf(entries.single), LedgerRole.ownTransfer);
    });

    test('to an account that is not the person\'s stays spending', () async {
      await ingestor.ingest([_pesalink()], _kcb);
      final [out] = await rows();
      expect(out.transferAccountId, isNull);
    });
  });

  test('a salary advance repayment pays down its debt', () async {
    await ingestor.ingest([
      _loanRepaid('12000.00', '48500.25', DateTime.utc(2026, 11, 5, 16, 40)),
    ], _kcb);

    final [paid] = await rows();
    expect(paid.kind, TransactionKind.loanRepayment);
    expect(paid.owedAfterMinor, 4850025);
    expect(paid.owedDueAt, isNotNull);
    final debts = DriftDebtsRepository(db);
    var [debt] = await debts.debts(today: CalendarDate(2026, 11, 6));
    expect(debt.lender, 'KCB Salary Advance');
    expect(debt.type, DebtType.salaryAdvance);
    expect(debt.balanceMinor, 4850025);
    expect(paid.debtId, debt.id);
    expect((await debts.startingBalances())[debt.id], 6050025);

    final entries = await transactionsRepo.ledgerEntries(
      from: DateTime.utc(2026, 11),
      to: DateTime.utc(2026, 12),
    );
    expect(roleOf(entries.single), LedgerRole.debtRepayment);

    // The next repayment's message sets the balance it states.
    await ingestor.ingest([
      _loanRepaid('12000.00', '36500.25', DateTime.utc(2026, 12, 5, 16, 40)),
    ], _kcb);
    [debt] = await debts.debts(today: CalendarDate(2026, 12, 6));
    expect(debt.balanceMinor, 3650025);
    expect(await db.select(db.debts).get(), hasLength(1));
  });

  group('KCB card', () {
    test('a declined payment is never a transaction', () async {
      final summary = await ingestor.ingest([
        _kcbSms(
          'USD 3.50 transaction made on KCB card 4111***0007 at '
          'example-store.co on 21/10/2026 20:41pm has been declined. Reason '
          '- Insufficient funds.Balance KESKES 0.00. Queries call '
          '+254700000000. Pata extra cash with a flexible Mobile Loan. Dial '
          '*000# or use',
          DateTime.utc(2026, 10, 21, 17, 41),
        ),
      ], _kcb);
      expect(summary.added, 0);
      expect(summary.forReview, 0, reason: 'a known notice, not a question');
      expect(await rows(), isEmpty);
    });

    test(
      'a declined payment an older pack queued leaves the review inbox',
      () async {
        final declined = _kcbSms(
          'KES 1,250.00 transaction made on KCB card 4111***0007 at EXAMPLE '
          'GROCERS on 02/11/2026 09:05am has been declined. Reason - '
          'Insufficient funds.Balance KES 120.00. Queries call +254711087000.',
          DateTime.utc(2026, 11, 2, 6, 5),
        );
        final inbox = DriftReviewInboxRepository(
          db,
          clock: () => DateTime.utc(2026, 11, 7),
        );
        await inbox.addIfNew(
          institutionId: 'kcb',
          sender: 'KCB',
          receivedAt: declined.receivedAt,
          messageHash: hashMessageBody(declined.body),
          body: declined.body,
          reason: 'No rule matched',
        );
        expect(await inbox.watchPending().first, hasLength(1));

        final summary = await SmsIngestor(
          accounts: DriftAccountsRepository(db),
          transactions: transactionsRepo,
          reviewInbox: inbox,
          reads: MessageReadsRepository(db),
        ).ingest([declined], _kcb);
        expect(summary.forReview, 0);
        expect(await inbox.watchPending().first, isEmpty);
        expect(await rows(), isEmpty);
      },
    );

    SmsMessage card() => _kcbSms(
      'USD 42.50 transaction made on KCB card 4111***0007 at '
      'example-store.co on 22/10/2026 21:05pm, Avail balance KES 2,310.40 '
      'Enquiries call +254700000000.',
      DateTime.utc(2026, 10, 22, 18, 6),
    );
    SmsMessage cardDebit() => _movement(
      'debited',
      '5,482.50',
      'Card Purchase',
      '21:06:10',
      date: '22 OCT 2026',
    );
    // One KES bought 0.0078 USD that day.
    const rates = CurrencyConverter(base: 'KES', ownRates: {'USD': 0.0078});

    SmsIngestor withRates() => SmsIngestor(
      accounts: DriftAccountsRepository(db),
      transactions: DriftTransactionsRepository(db, converter: rates),
      reviewInbox: DriftReviewInboxRepository(db),
    );

    Future<List<LedgerEntry>> inKes() => DriftTransactionsRepository(
      db,
      converter: rates,
    ).ledgerEntries(from: DateTime.utc(2026, 10), to: DateTime.utc(2026, 11));

    test('in USD on the KES account, estimated from the day\'s rate', () async {
      await withRates().ingest([card()], _kcb);
      final kcb = await account('kcb');
      expect(kcb.currency, 'KES');
      expect(await db.select(db.accounts).get(), hasLength(1));
      final [row] = await rows();
      expect((row.currency, row.amountMinor), ('USD', 4250));
      expect(row.fxRateMicros, isNull);
      final [entry] = await inKes();
      expect(entry.originalCurrency, 'USD');
      expect(entry.originalAmountMinor, 4250);
      expect(entry.currency, 'KES');
      expect(entry.amountMinor, 544872); // USD 42.50 / 0.0078
    });

    for (final cardFirst in [true, false]) {
      test('with its KES debit, one payment at the rate got '
          '(${cardFirst ? 'card' : 'debit'} first)', () async {
        final ingest = withRates();
        final messages = [card(), cardDebit()];
        for (final m in cardFirst ? messages : messages.reversed) {
          await ingest.ingest([m], _kcb);
        }
        final [row] = await rows();
        expect((row.currency, row.amountMinor), ('USD', 4250));
        expect(row.counterpartyName, 'example-store.co');
        expect(row.fxRateCurrency, 'KES');
        final [entry] = await inKes();
        expect(entry.originalCurrency, 'USD');
        expect(entry.originalAmountMinor, 4250);
        // KES 5,482.50, as near as the rate's millionths keep it.
        expect(entry.amountMinor, closeTo(548250, 5));
        expect((await account('kcb')).currency, 'KES');
      });
    }

    test('a KES debit far from the card amount stays its own', () async {
      await withRates().ingest([
        card(),
        _movement('debited', '900.00', 'Mobi', '21:07:00', date: '22 OCT 2026'),
      ], _kcb);
      expect(await rows(), hasLength(2));
    });

    test('an approved payment in USD is spent from the KCB account', () async {
      await ingestor.ingest([
        _movement('credited', '1,000.00', 'Mobi', '08:00:00'),
        _kcbSms(
          'USD 42.50 transaction made on KCB card 4111***0007 at '
          'example-store.co on 22/10/2026 21:05pm, Avail balance KES 2,310.40 '
          'Enquiries call +254700000000.',
          DateTime.utc(2026, 10, 22, 18, 6),
        ),
      ], _kcb);
      final card = (await rows()).first;
      expect(card.currency, 'USD');
      expect(card.amountMinor, 4250);
      expect(card.counterpartyName, 'example-store.co');
      expect(card.balanceAfterMinor, isNull);
      expect(card.accountId, (await account('kcb')).id);
    });
  });
}
