import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/debts_repository.dart';
import 'package:pesaclarity/src/data/repositories/payees_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/debts/debt.dart';
import 'package:pesaclarity/src/domain/debts/repayment_matcher.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

void main() {
  late AppDatabase db;
  late DriftDebtsRepository debts;
  late DriftTransactionsRepository transactions;
  late int account;

  final today = CalendarDate(2026, 11, 20);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    debts = DriftDebtsRepository(db);
    transactions = DriftTransactionsRepository(db);
    account = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: DateTime.utc(2026),
          ),
        );
  });

  tearDown(() => db.close());

  Future<int> pay(
    int month,
    int day,
    int amount, {
    int? debtId,
    PayeeIdentifier? counterparty,
    TransactionKind kind = TransactionKind.paybill,
  }) => transactions.add(
    TransactionsCompanion.insert(
      accountId: account,
      occurredAt: DateTime.utc(2026, month, day, 9),
      amountMinor: amount,
      direction: TransactionDirection.outflow,
      kind: Value(kind),
      source: TransactionSource.sms,
      debtId: Value(debtId),
      counterpartyKind: Value(counterparty?.kind),
      counterpartyValue: Value(counterparty?.value),
    ),
  );

  test('what is owed is the starting balance less linked repayments', () async {
    final id = await debts.add(
      DebtsCompanion.insert(
        lender: 'Test Bank',
        type: DebtType.bankLoan,
        startingBalanceMinor: 100000,
        annualRateBasisPoints: const Value(1400),
        minimumPaymentMinor: const Value(10000),
      ),
    );
    await pay(10, 5, 10000, debtId: id);
    await pay(11, 5, 12000, debtId: id);
    await pay(11, 6, 999);

    final debt = (await debts.debts(today: today)).single;
    expect(debt.balanceMinor, 78000);
    expect(debt.annualRateBasisPoints, 1400);
    expect(debt.minimumPaymentMinor, 10000);
    expect(debt.isFormal, isTrue);

    await debts.confirmBalance(id, 90000, DateTime.utc(2026, 11));
    expect((await debts.debts(today: today)).single.balanceMinor, 78000);

    await debts.confirmBalance(id, 5000, DateTime.utc(2026, 11, 5, 10));
    expect((await debts.debts(today: today)).single.balanceMinor, 5000);
  });

  test('a family loan carries its unpaid instalments', () async {
    final id = await debts.add(
      DebtsCompanion.insert(
        lender: 'Test Aunt',
        type: DebtType.family,
        startingBalanceMinor: 30000,
        isFormal: const Value(false),
      ),
    );
    await debts.setInstalments(id, [
      DebtInstalment(dueDate: CalendarDate(2026, 10, 30), amountMinor: 10000),
      DebtInstalment(dueDate: CalendarDate(2026, 11, 30), amountMinor: 10000),
      DebtInstalment(dueDate: CalendarDate(2026, 12, 30), amountMinor: 10000),
    ]);
    await pay(10, 28, 4000, debtId: id, kind: TransactionKind.sent);

    final debt = (await debts.debts(today: today)).single;
    expect(debt.isFormal, isFalse);
    expect(debt.balanceMinor, 26000);
    expect(
      debt.instalments.first,
      DebtInstalment(dueDate: CalendarDate(2026, 10, 30), amountMinor: 6000),
    );
    expect(debt.instalments, hasLength(3));

    final status = await debts.familyStatus(id, today);
    expect(status!.overdueMinor, 6000);
    expect(status.paidMinor, 4000);
    expect(await debts.familyStatus(999, today), isNull);
  });

  test('keeps the custom order', () async {
    Future<int> add(String lender) => debts.add(
      DebtsCompanion.insert(
        lender: lender,
        type: DebtType.mobileLoan,
        startingBalanceMinor: 1000,
      ),
    );
    final a = await add('Test A');
    final b = await add('Test B');
    final c = await add('Test C');
    await debts.setCustomOrder([c, a]);
    expect(await debts.customOrder(), [c, a]);
    await debts.setCustomOrder([b]);
    expect(await debts.customOrder(), [b]);
  });

  test('suggests repayments, and stops once one is linked', () async {
    final paybill = PayeeIdentifier.paybill('400200', 'LOAN 1')!;
    final payee = await DriftPayeesRepository(db)
        .name(paybill, displayName: 'Test Bank');
    final loan = await debts.add(
      DebtsCompanion.insert(
        lender: 'Test Lender',
        type: DebtType.bankLoan,
        startingBalanceMinor: 100000,
        minimumPaymentMinor: const Value(5000),
        payeeId: Value(payee),
      ),
    );
    final fuliza = await debts.add(
      DebtsCompanion.insert(
        lender: 'Fuliza',
        type: DebtType.fuliza,
        startingBalanceMinor: 0,
      ),
    );
    final repayment = await pay(11, 2, 5000, counterparty: paybill);
    final fulizaRepayment = await pay(
      11,
      3,
      505,
      kind: TransactionKind.fulizaRepayment,
    );
    await pay(11, 4, 5000);

    Future<List<RepaymentSuggestion>> suggestions() =>
        debts.repaymentSuggestions(
          from: DateTime.utc(2026, 11),
          to: DateTime.utc(2026, 12),
          today: today,
        );

    expect(await suggestions(), [
      RepaymentSuggestion(
        entryId: repayment,
        debtId: loan,
        match: RepaymentMatch.payeeAndAmount,
      ),
      RepaymentSuggestion(
        entryId: fulizaRepayment,
        debtId: fuliza,
        match: RepaymentMatch.fuliza,
      ),
    ]);

    await debts.linkRepayment(repayment, loan);
    expect((await suggestions()).map((s) => s.entryId), [fulizaRepayment]);
    final owed = {
      for (final d in await debts.debts(today: today)) d.id: d.balanceMinor,
    };
    expect(owed[loan], 95000);
    expect(
      (await debts.debts(today: today))
          .firstWhere((d) => d.id == loan)
          .identifiers,
      [paybill],
    );
  });

  test('removing a debt unlinks its repayments and instalments', () async {
    final id = await debts.add(
      DebtsCompanion.insert(
        lender: 'Test Friend',
        type: DebtType.family,
        startingBalanceMinor: 5000,
      ),
    );
    await debts.setInstalments(id, [
      DebtInstalment(dueDate: CalendarDate(2026, 12, 1), amountMinor: 5000),
    ]);
    final tx = await pay(11, 1, 1000, debtId: id);
    await debts.remove(id);

    expect(await debts.debts(today: today), isEmpty);
    expect(await db.select(db.debtInstalments).get(), isEmpty);
    final record = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(tx))).getSingle();
    expect(record.debtId, isNull);
  });

  group('next due date', () {
    Future<int> loan() => debts.add(
      DebtsCompanion.insert(
        lender: 'Test Bank Loan',
        type: DebtType.bankLoan,
        startingBalanceMinor: 100000,
        minimumPaymentMinor: const Value(10000),
      ),
    );

    Future<Debt> read(int id) async =>
        (await debts.debts(today: today)).singleWhere((d) => d.id == id);

    test('a typed date is kept, with no message behind it', () async {
      final id = await loan();
      expect((await read(id)).nextDue, isNull);

      await debts.setNextDue(
        id,
        CalendarDate(2026, 12, 5),
        DateTime.utc(2026, 11, 20),
      );
      final due = (await read(id)).nextDue!;
      expect(due.date, CalendarDate(2026, 12, 5));
      expect(due.source, isNull);
      expect(due.paidSince, isFalse);

      await debts.setNextDue(id, null, DateTime.utc(2026, 11, 21));
      expect((await read(id)).nextDue, isNull);
      final row = await (db.select(
        db.debts,
      )..where((d) => d.id.equals(id))).getSingle();
      expect(row.nextDueSetAt, isNull);
    });

    test('a repayment on or after the date counts as paid since', () async {
      final id = await loan();
      await debts.setNextDue(
        id,
        CalendarDate(2026, 11, 10),
        DateTime.utc(2026, 11),
      );
      await pay(11, 9, 10000, debtId: id);
      expect((await read(id)).nextDue!.paidSince, isFalse);

      // 09:00 UTC on 10 Nov is 12:00 that day in Nairobi.
      await pay(11, 10, 10000, debtId: id);
      expect((await read(id)).nextDue!.paidSince, isTrue);
    });

    test('a payment by hand counts as paid since too', () async {
      final id = await loan();
      await debts.setNextDue(
        id,
        CalendarDate(2026, 11, 10),
        DateTime.utc(2026, 11),
      );
      await debts.recordPayment(id, DateTime.utc(2026, 11, 12), 5000);
      final debt = await read(id);
      expect(debt.nextDue!.paidSince, isTrue);
      expect(debt.lastPayment, (
        date: CalendarDate(2026, 11, 12),
        amountMinor: 5000,
      ));
    });

    test('the last payment is the latest repayment', () async {
      final id = await loan();
      expect((await read(id)).lastPayment, isNull);
      await pay(11, 15, 7000, debtId: id);
      await pay(10, 15, 9000, debtId: id);
      expect((await read(id)).lastPayment, (
        date: CalendarDate(2026, 11, 15),
        amountMinor: 7000,
      ));
    });

    test('names the message the date came from, until it is deleted', () async {
      final id = await loan();
      final tx = await pay(11, 15, 10000, debtId: id);
      await (db.update(db.debts)..where((d) => d.id.equals(id))).write(
        DebtsCompanion(
          nextDueDay: const Value(20261215),
          nextDueSetAt: Value(DateTime.utc(2026, 11, 15, 9)),
          nextDueTransactionId: Value(tx),
        ),
      );
      final source = (await read(id)).nextDue!.source!;
      expect(source.readAt.toUtc(), DateTime.utc(2026, 11, 15, 9));
      expect(source.account, 'M-Pesa');

      await (db.delete(db.transactions)..where((t) => t.id.equals(tx))).go();
      final due = (await read(id)).nextDue!;
      expect(due.date, CalendarDate(2026, 12, 15));
      expect(due.source, isNull);
    });
  });
}
