import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/debts/application/debt_plan_provider.dart';
import 'package:pesaclarity/src/features/debts/presentation/debts_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // 26 October 2026, 08:00 EAT.
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 26, 5)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<int> addDebt(String lender, int balance, int minimum) => db
      .into(db.debts)
      .insert(
        DebtsCompanion.insert(
          lender: lender,
          type: DebtType.mobileLoan,
          startingBalanceMinor: balance,
          minimumPaymentMinor: Value(minimum),
        ),
      );

  test('is null with nothing owed', () async {
    expect(await container().read(debtPlanProvider.future), isNull);
  });

  test('plans from this month, in the custom order when set', () async {
    final a = await addDebt('Test A', 3000, 1000);
    final b = await addDebt('Test B', 2000, 1000);
    await db.customStatement('UPDATE debts SET custom_order = 0 WHERE id = $a');

    final plan = (await container().read(debtPlanProvider.future))!;
    expect(plan.plan.startMonth, YearMonth(2026, 10));
    expect(plan.plan.order, [a, b]);
    expect(plan.plan.debtFreeMonth, YearMonth(2026, 12));
  });

  test('labels months briefly', () {
    expect(monthLabel(YearMonth(2028, 3)), 'Mar 2028');
  });
}
