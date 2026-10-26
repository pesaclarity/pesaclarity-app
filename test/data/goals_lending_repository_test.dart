import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/debts_repository.dart';
import 'package:pesaclarity/src/data/repositories/goals_repository.dart';
import 'package:pesaclarity/src/data/repositories/lending_repository.dart';
import 'package:pesaclarity/src/domain/debts/debt.dart';
import 'package:pesaclarity/src/domain/goals/savings_goal.dart';
import 'package:pesaclarity/src/domain/lending/lent_loan.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('goals', () {
    test('adds, edits and deletes a goal', () async {
      final goals = DriftGoalsRepository(db);
      final id = await goals.add(
        name: 'New laptop',
        targetMinor: 30000000,
        savedMinor: 3600000,
        targetDate: CalendarDate(2027, 6, 30),
      );
      var saved = (await goals.goals()).single;
      expect(saved.name, 'New laptop');
      expect(saved.savedMinor, 3600000);
      expect(saved.targetDate, CalendarDate(2027, 6, 30));
      expect(saved.status, GoalStatus.active);

      await goals.update(
        SavingsGoal(
          id: id,
          name: 'Laptop',
          targetMinor: 30000000,
          savedMinor: 30000000,
        ),
      );
      saved = (await goals.goals()).single;
      expect(saved.name, 'Laptop');
      expect(saved.targetDate, isNull);
      expect(saved.status, GoalStatus.achieved);

      await goals.remove(id);
      expect(await goals.goals(), isEmpty);
    });

    test('deleting a goal unlinks its transactions', () async {
      final goals = DriftGoalsRepository(db);
      final id = await goals.add(name: 'Fees', targetMinor: 100);
      final account = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'M-Pesa',
              type: AccountType.mpesa,
              openingDate: DateTime.utc(2026),
            ),
          );
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: account,
              occurredAt: DateTime.utc(2026, 10),
              amountMinor: 100,
              direction: TransactionDirection.outflow,
              source: TransactionSource.manual,
              goalId: Value(id),
            ),
          );
      await db.customStatement('PRAGMA foreign_keys = ON');
      await goals.remove(id);
      expect((await db.select(db.transactions).getSingle()).goalId, isNull);
    });
  });

  group('lent', () {
    test('records loans, part payments and deletes with payments', () async {
      final lending = DriftLendingRepository(db);
      final id = await lending.add(
        person: 'John',
        amountMinor: 500000,
        lentOn: CalendarDate(2026, 10, 3),
        dueDate: CalendarDate(2026, 10, 31),
        note: 'Rent top-up',
      );
      await lending.recordPayment(id, DateTime.utc(2026, 10, 20, 9), 200000);

      final loan = (await lending.lent()).single;
      expect(loan.person, 'John');
      expect(loan.lentOn, CalendarDate(2026, 10, 3));
      expect(loan.dueDate, CalendarDate(2026, 10, 31));
      expect(loan.note, 'Rent top-up');
      expect(loan.payments.single.amountMinor, 200000);
      expect(loan.status(CalendarDate(2026, 11, 1)).remainingMinor, 300000);

      await lending.remove(id);
      expect(await lending.lent(), isEmpty);
      expect(await db.select(db.loanPayments).get(), isEmpty);
    });

    test('edits keep the payments', () async {
      final lending = DriftLendingRepository(db);
      final id = await lending.add(
        person: 'John',
        amountMinor: 500000,
        lentOn: CalendarDate(2026, 10, 3),
      );
      await lending.recordPayment(id, DateTime.utc(2026, 10, 20), 100000);
      final loan = (await lending.lent()).single;
      await lending.update(
        LentLoan(
          id: loan.id,
          person: 'John K',
          amountMinor: 600000,
          lentOn: loan.lentOn,
        ),
      );
      final edited = (await lending.lent()).single;
      expect(edited.person, 'John K');
      expect(edited.amountMinor, 600000);
      expect(edited.payments, hasLength(1));
    });
  });

  group('family debts paid by hand', () {
    test('count in the balance, the instalments and repaid totals', () async {
      final debts = DriftDebtsRepository(db);
      final id = await debts.add(
        DebtsCompanion.insert(
          lender: 'Family loan',
          type: DebtType.family,
          startingBalanceMinor: 2100000,
          isFormal: const Value(false),
        ),
      );
      await debts.setInstalments(id, [
        DebtInstalment(
          dueDate: CalendarDate(2026, 11, 30),
          amountMinor: 1000000,
        ),
        DebtInstalment(
          dueDate: CalendarDate(2026, 12, 31),
          amountMinor: 1100000,
        ),
      ]);
      await debts.recordPayment(id, DateTime.utc(2026, 10, 10), 400000);

      final today = CalendarDate(2026, 10, 26);
      final debt = (await debts.debts(today: today)).single;
      expect(debt.balanceMinor, 1700000);
      expect(debt.instalments.first.amountMinor, 600000);
      expect((await debts.familyStatus(id, today))!.paidMinor, 400000);
      expect(await debts.startingBalances(), {id: 2100000});
      expect(
        await debts.repaidBetween(
          DateTime.utc(2026, 10),
          DateTime.utc(2026, 11),
        ),
        400000,
      );
      expect(
        await debts.repaidBetween(
          DateTime.utc(2026, 11),
          DateTime.utc(2026, 12),
        ),
        0,
      );
    });
  });
}
