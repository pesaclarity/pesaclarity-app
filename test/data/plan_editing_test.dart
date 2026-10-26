import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/payday_repository.dart';
import 'package:pesaclarity/src/data/repositories/plan_repository.dart';
import 'package:pesaclarity/src/domain/plan/month_plan.dart';
import 'package:pesaclarity/src/domain/plan/month_snapshot.dart';
import 'package:pesaclarity/src/domain/plan/plan_inputs.dart' as plan;
import 'package:pesaclarity/src/domain/time/calendar.dart';

void main() {
  late AppDatabase db;
  late DriftPlanRepository repository;
  late int rent;

  final october = YearMonth(2026, 10);
  final november = YearMonth(2026, 11);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftPlanRepository(db);
    rent = await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(name: 'Rent', type: CategoryType.expense),
        );
  });

  tearDown(() => db.close());

  Future<int> addRent({CalendarDate? start}) => repository.saveRecurring(
    name: 'Rent',
    categoryId: rent,
    amountMinor: 2500000,
    frequency: RecurrenceFrequency.monthly,
    startDate: start ?? CalendarDate(2026, 9, 5),
  );

  group('recurring bills', () {
    test('adds and edits a bill', () async {
      final id = await addRent();
      var lines = (await repository.monthPlan(november)).lines;
      expect(lines.single.dueDate, CalendarDate(2026, 11, 5));

      await repository.saveRecurring(
        id: id,
        name: 'Rent, Kilimani',
        categoryId: rent,
        amountMinor: 2800000,
        frequency: RecurrenceFrequency.monthly,
        startDate: CalendarDate(2026, 9, 1),
      );
      lines = (await repository.monthPlan(november)).lines;
      expect(lines.single.name, 'Rent, Kilimani');
      expect(lines.single.amountMinor, 2800000);
      expect(lines.single.dueDate, CalendarDate(2026, 11, 1));
    });

    test('deleting from a month keeps it in earlier months', () async {
      final id = await addRent();
      await repository.stopRecurring(id, from: november);

      expect((await repository.monthPlan(october)).lines, hasLength(1));
      expect((await repository.monthPlan(november)).lines, isEmpty);
      expect(
        (await repository.recurringBill(id))!.endDate,
        CalendarDate(2026, 10, 31),
      );
    });

    test('deleting from its first month removes it', () async {
      final id = await addRent(start: CalendarDate(2026, 11, 5));
      await repository.stopRecurring(id, from: november);
      expect(await repository.recurringBill(id), isNull);
    });
  });

  group('one-offs', () {
    test('adds, marks paid and deletes a one-off', () async {
      final id = await repository.saveBudgetItem(
        plan.BudgetItem(
          month: november,
          name: 'Wedding gift',
          amountMinor: 500000,
          kind: BudgetItemKind.oneOff,
        ),
      );
      var line = (await repository.monthPlan(november)).lines.single;
      expect(line.source, PlanLineSource.oneOff);
      expect(line.isMarkedPaid, isFalse);
      expect((await repository.monthPlan(october)).lines, isEmpty);

      await repository.saveBudgetItem(
        plan.BudgetItem(
          id: id,
          month: november,
          name: 'Wedding gift',
          amountMinor: 600000,
          kind: BudgetItemKind.oneOff,
          isPaid: true,
        ),
      );
      line = (await repository.monthPlan(november)).lines.single;
      expect(line.amountMinor, 600000);
      expect(line.isMarkedPaid, isTrue);

      await repository.deleteBudgetItem(id);
      expect((await repository.monthPlan(november)).lines, isEmpty);
    });
  });

  test('the plan starts at the earliest bill or one-off', () async {
    expect(await repository.firstPlanMonth(), isNull);
    await addRent();
    await repository.saveBudgetItem(
      plan.BudgetItem(
        month: YearMonth(2026, 8),
        name: 'Phone repair',
        amountMinor: 300000,
        kind: BudgetItemKind.oneOff,
      ),
    );
    expect(await repository.firstPlanMonth(), YearMonth(2026, 8));
  });

  test('reads back a frozen month with its carried arrears', () async {
    await addRent();
    final review = MonthReview.of(await repository.monthPlan(october), []);
    await repository.saveSnapshot(
      MonthSnapshot.freeze(review, now: DateTime.utc(2026, 11, 2)),
    );

    expect(await repository.snapshot(november), isNull);
    final frozen = (await repository.snapshot(october))!;
    expect(frozen.categories.single.plannedMinor, 2500000);
    expect(frozen.categories.single.actualMinor, 0);
    expect(frozen.carriedArrears.single.amountMinor, 2500000);
    final novemberLines = (await repository.monthPlan(november)).lines;
    expect(
      novemberLines.map((l) => l.source),
      containsAll([PlanLineSource.recurring, PlanLineSource.arrears]),
    );
  });

  test('remembers the surplus split', () async {
    expect(await repository.surplusDebtShareBasisPoints(), 5000);
    await repository.setSurplusDebtShareBasisPoints(7500);
    expect(await repository.surplusDebtShareBasisPoints(), 7500);
    expect(
      () => repository.setSurplusDebtShareBasisPoints(10001),
      throwsArgumentError,
    );
  });

  test('payday ticks and dismissal are kept per month', () async {
    final payday = DriftPaydayRepository(db);
    expect(await payday.ticked(november), isEmpty);
    await payday.setTicked(november, 'debt:1', true);
    await payday.setTicked(november, 'day-to-day', true);
    await payday.setTicked(november, 'debt:1', false);
    expect(await payday.ticked(november), {'day-to-day'});
    expect(await payday.ticked(october), isEmpty);

    expect(await payday.isDismissed(november), isFalse);
    await payday.dismiss(november);
    expect(await payday.isDismissed(november), isTrue);
  });
}
