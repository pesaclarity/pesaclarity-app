import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/debts_repository.dart';
import 'package:pesaclarity/src/data/repositories/review_inbox_repository.dart';
import 'package:pesaclarity/src/data/repositories/space_move_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/debts/debt.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';

import 'package:ujumbe/ujumbe.dart' show SmsMessage;

import '../helpers/sms_samples.dart';

void main() {
  late AppDatabase personal;
  late AppDatabase business;
  late DriftSpaceMoveRepository moves;
  late int mpesa;

  TransactionsCompanion sale(int accountId, {String key = 'QK1|150000|t'}) =>
      TransactionsCompanion.insert(
        accountId: accountId,
        occurredAt: DateTime.utc(2026, 11, 3, 9),
        amountMinor: 150000,
        direction: TransactionDirection.inflow,
        kind: const Value(TransactionKind.received),
        source: TransactionSource.sms,
        counterpartyName: const Value('TEST CUSTOMER'),
        receiptNo: const Value('QK1'),
        dedupeKey: Value(key),
      );

  setUp(() async {
    personal = AppDatabase(NativeDatabase.memory());
    business = AppDatabase(NativeDatabase.memory());
    await business.becomeSpace(SpaceKind.business);
    moves = DriftSpaceMoveRepository(
      personal,
      (spaceId) async => (business, false),
    );
    mpesa = await personal
        .into(personal.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: DateTime.utc(2026),
            institutionId: const Value('mpesa'),
          ),
        );
  });

  tearDown(() async {
    await personal.close();
    await business.close();
  });

  test('moves a transaction, its account and its category key', () async {
    final id = await DriftTransactionsRepository(personal).add(sale(mpesa));
    final received = await (personal.select(
      personal.categories,
    )..where((c) => c.key.equals('money_received'))).getSingle();
    await (personal.update(personal.transactions)
          ..where((t) => t.id.equals(id)))
        .write(TransactionsCompanion(categoryOverrideId: Value(received.id)));

    await moves.move(id, 'abc123');

    expect(await personal.select(personal.transactions).get(), isEmpty);
    final moved = await business.select(business.transactions).getSingle();
    expect(moved.amountMinor, 150000);
    expect(moved.receiptNo, 'QK1');
    final account = await business.select(business.accounts).getSingle();
    expect(account.institutionId, 'mpesa');
    expect(moved.accountId, account.id);
    final category = await (business.select(
      business.categories,
    )..where((c) => c.id.equals(moved.categoryOverrideId!))).getSingle();
    expect(category.key, 'money_received');

    // Reading the same message again in Personal does not bring it back.
    final added = await DriftTransactionsRepository(personal)
        .addNew([sale(mpesa)]);
    expect(added, 0);
    final other = await DriftTransactionsRepository(personal)
        .addNew([sale(mpesa, key: 'QK2|150000|t')]);
    expect(other, 1);
  });

  test('a category the other space lacks is left unset', () async {
    final id = await DriftTransactionsRepository(personal).add(sale(mpesa));
    final betting = await (personal.select(
      personal.categories,
    )..where((c) => c.key.equals('betting'))).getSingle();
    await (personal.update(personal.transactions)
          ..where((t) => t.id.equals(id)))
        .write(TransactionsCompanion(categoryOverrideId: Value(betting.id)));

    await moves.move(id, 'abc123');
    final moved = await business.select(business.transactions).getSingle();
    expect(moved.categoryOverrideId, isNull);
  });

  // A debt or goal belongs to its own space: its row id means another debt
  // or goal, or none, in any other. Synthetic messages only.
  group('a payment linked to a debt or goal', () {
    final today = CalendarDate(2026, 11, 20);
    late DriftDebtsRepository personalDebts;

    /// Reads [messages] into Personal as its KCB account's; a loan
    /// repayment is linked to its debt on the way (linkLoanRepayment).
    Future<void> read(List<SmsMessage> messages) async {
      final summary =
          await SmsIngestor(
            accounts: DriftAccountsRepository(personal),
            transactions: DriftTransactionsRepository(personal),
            reviewInbox: DriftReviewInboxRepository(personal),
            parse: (packs, messages) async => parseAll(packs, messages),
          ).ingest(messages, [
            institutionCatalogue.singleWhere((i) => i.id == 'kcb'),
          ]);
      expect(summary.added, messages.length);
    }

    Future<List<TransactionRecord>> repayments() => (personal.select(
      personal.transactions,
    )..orderBy([(t) => OrderingTerm.asc(t.occurredAt)])).get();

    Future<Debt> loan() async =>
        (await personalDebts.debts(today: today)).single;

    final november = kcbLoanRepaid(
      '5,000.00',
      '15,000.00',
      DateTime.utc(2026, 11, 18, 7),
    );
    final october = kcbLoanRepaid(
      '5,000.00',
      '20,000.00',
      DateTime.utc(2026, 10, 18, 7),
      due: '05/11/2026',
    );

    setUp(() => personalDebts = DriftDebtsRepository(personal));

    test('moved to a business that owes a supplier, it does not pay the '
        'supplier', () async {
      await read([november]);
      final repayment = (await repayments()).single;
      final debt = await personal.select(personal.debts).getSingle();
      expect((repayment.debtId, debt.lender), (debt.id, 'KCB Salary Advance'));
      // The shop's first debt has the same row id as Personal's loan.
      final supplier = await business
          .into(business.debts)
          .insert(
            DebtsCompanion.insert(
              lender: 'Unga Wholesalers',
              type: DebtType.supplier,
              startingBalanceMinor: 2000000,
              isFormal: const Value(false),
            ),
          );
      expect(supplier, debt.id);

      await moves.move(repayment.id, 'shop1');

      final moved = await business.select(business.transactions).getSingle();
      expect(moved.debtId, isNull);
      expect(moved.amountMinor, 500000);
      final owed = (await DriftDebtsRepository(business).debts(today: today))
          .single;
      expect((owed.lender, owed.balanceMinor), ('Unga Wholesalers', 2000000));
    });

    test('moved to a space with no debts, it moves', () async {
      await read([november]);
      await moves.move((await repayments()).single.id, 'shop1');

      expect(await repayments(), isEmpty);
      final moved = await business.select(business.transactions).getSingle();
      expect(moved.debtId, isNull);
      expect(await business.select(business.debts).get(), isEmpty);
    });

    test('the space it left stops counting it: the loan is as it was before '
        'that payment', () async {
      await read([november]);
      var debt = await loan();
      expect(debt.balanceMinor, 1500000);
      expect(debt.nextDue!.date, CalendarDate(2026, 12, 5));

      await moves.move((await repayments()).single.id, 'shop1');

      debt = await loan();
      // KES 20,000.00: what was owed before the KES 5,000.00 now elsewhere.
      expect(debt.balanceMinor, 2000000);
      expect(debt.nextDue, isNull);
      expect(debt.lastPayment, isNull);
      final row = await personal.select(personal.debts).getSingle();
      expect((row.balanceMinor, row.balanceAsOf), (null, null));
      expect((row.nextDueDay, row.nextDueSetAt), (null, null));
    });

    test('with an earlier repayment still there, the loan goes back to what '
        'its message said', () async {
      await read([october, november]);
      final [first, second] = await repayments();
      expect((await loan()).balanceMinor, 1500000);

      await moves.move(second.id, 'shop1');

      final debt = await loan();
      expect(debt.balanceMinor, 2000000);
      expect(debt.nextDue!.date, CalendarDate(2026, 11, 5));
      expect(
        debt.nextDue!.source!.readAt.toUtc(),
        DateTime.utc(2026, 10, 18, 7),
      );
      expect(debt.lastPayment, (
        date: CalendarDate(2026, 10, 18),
        amountMinor: 500000,
      ));
      final row = await personal.select(personal.debts).getSingle();
      expect(row.nextDueTransactionId, first.id);
    });

    test('moving an earlier repayment leaves what the newest message '
        'said', () async {
      await read([october, november]);
      final [first, second] = await repayments();

      await moves.move(first.id, 'shop1');

      final debt = await loan();
      expect(debt.balanceMinor, 1500000);
      expect(debt.nextDue!.date, CalendarDate(2026, 12, 5));
      final row = await personal.select(personal.debts).getSingle();
      expect(row.nextDueTransactionId, second.id);
    });

    test('a balance or due date the person set since stays', () async {
      await read([november]);
      final id = (await loan()).id;
      await personalDebts.confirmBalance(
        id,
        1400000,
        DateTime.utc(2026, 11, 19),
      );
      await personalDebts.setNextDue(
        id,
        CalendarDate(2026, 12, 10),
        DateTime.utc(2026, 11, 19),
      );

      await moves.move((await repayments()).single.id, 'shop1');

      final debt = await loan();
      expect(debt.balanceMinor, 1400000);
      expect(debt.nextDue!.date, CalendarDate(2026, 12, 10));
    });

    test('a payment the person linked by hand: the debt is owed in full '
        'again once it moves', () async {
      final debt = await personalDebts.add(
        DebtsCompanion.insert(
          lender: 'Test Bank',
          type: DebtType.bankLoan,
          startingBalanceMinor: 1000000,
        ),
      );
      final id = await DriftTransactionsRepository(personal).add(sale(mpesa));
      await (personal.update(
        personal.transactions,
      )..where((t) => t.id.equals(id))).write(
        const TransactionsCompanion(
          direction: Value(TransactionDirection.outflow),
        ),
      );
      await personalDebts.linkRepayment(id, debt);
      expect((await loan()).balanceMinor, 850000);

      await moves.move(id, 'shop1');

      expect((await loan()).balanceMinor, 1000000);
      final moved = await business.select(business.transactions).getSingle();
      expect(moved.debtId, isNull);
    });

    test('moved back, it comes back without its link: the person links it '
        'again', () async {
      await read([november]);
      await moves.move((await repayments()).single.id, 'shop1');
      final there = await business.select(business.transactions).getSingle();

      await DriftSpaceMoveRepository(
        business,
        (spaceId) async => (personal, false),
      ).move(there.id, personalSpaceId);

      final back = (await repayments()).single;
      expect(back.debtId, isNull);
      expect((await loan()).balanceMinor, 2000000);
    });

    test('a goal does not cross either', () async {
      Future<int> goal(AppDatabase db, String name) => db
          .into(db.goals)
          .insert(GoalsCompanion.insert(name: name, targetMinor: 5000000));
      final mine = await goal(personal, 'School fees');
      // The same row id, another goal.
      expect(await goal(business, 'New fridge'), mine);
      final id = await DriftTransactionsRepository(personal).add(sale(mpesa));
      await (personal.update(personal.transactions)
            ..where((t) => t.id.equals(id)))
          .write(TransactionsCompanion(goalId: Value(mine)));

      await moves.move(id, 'shop1');

      final moved = await business.select(business.transactions).getSingle();
      expect(moved.goalId, isNull);
    });

    test('a goal that the other space does not have: it still moves', () async {
      final mine = await personal
          .into(personal.goals)
          .insert(
            GoalsCompanion.insert(name: 'School fees', targetMinor: 5000000),
          );
      final id = await DriftTransactionsRepository(personal).add(sale(mpesa));
      await (personal.update(personal.transactions)
            ..where((t) => t.id.equals(id)))
          .write(TransactionsCompanion(goalId: Value(mine)));

      await moves.move(id, 'shop1');

      expect(await personal.select(personal.transactions).get(), isEmpty);
      expect(await business.select(business.transactions).get(), hasLength(1));
    });
  });
}
