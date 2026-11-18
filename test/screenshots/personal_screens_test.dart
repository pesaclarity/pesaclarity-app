// Personal screens for the marketing screenshots: a made-up salaried
// person's months, drawn by the app's own widgets (README, Screenshots).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/debts_repository.dart';
import 'package:pesaclarity/src/data/repositories/goals_repository.dart';
import 'package:pesaclarity/src/data/repositories/lending_repository.dart';
import 'package:pesaclarity/src/data/repositories/plan_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/budget/safe_to_spend.dart';
import 'package:pesaclarity/src/domain/income/income_sources.dart';
import 'package:pesaclarity/src/domain/ledger/own_transfers.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/debts/presentation/debts_screen.dart';
import 'package:pesaclarity/src/features/goals/presentation/goals_screen.dart';
import 'package:pesaclarity/src/features/home/presentation/home_screen.dart';
import 'package:pesaclarity/src/features/income/application/income_providers.dart';
import 'package:pesaclarity/src/features/insights/presentation/insights_screen.dart';
import 'package:pesaclarity/src/features/plan/presentation/plan_screen.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';

/// Thursday 19 November 2026, 09:30 in Nairobi.
final _now = eat(2026, 11, 19, 9, 30);

/// Someone paid a salary on the 25th into the bank, who spends from M-Pesa,
/// with a plan, two debts, two goals and a little lent out.
class _Person {
  _Person(this.db);

  final AppDatabase db;
  late int bank;
  late int mpesa;
  late int fund;
  late int bankLoan;
  late int familyLoan;
  final _categories = <String, int>{};
  var _code = 1;

  Future<int> _category(String key) async =>
      _categories[key] ??= (await (db.select(
        db.categories,
      )..where((c) => c.key.equals(key))).getSingle()).id;

  Future<int> tx(
    int account,
    DateTime at,
    int shillings, {
    required bool inflow,
    required String name,
    String? category,
    TransactionKind? kind,
    int feeShillings = 0,
    int? debt,
  }) async => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: account,
          occurredAt: at,
          amountMinor: kes(shillings),
          direction: inflow
              ? TransactionDirection.inflow
              : TransactionDirection.outflow,
          kind: Value(
            kind ?? (inflow ? TransactionKind.received : TransactionKind.sent),
          ),
          feeMinor: Value(kes(feeShillings)),
          source: TransactionSource.sms,
          counterpartyName: Value(name),
          receiptNo: Value('TK${(_code++).toString().padLeft(8, '0')}'),
          categoryOverrideId: Value(
            category == null ? null : await _category(category),
          ),
          debtId: Value(debt),
        ),
      );

  Future<void> seed() async {
    final settings = DriftAppSettingsRepository(db);
    await settings.writeJson(
      IncomeSourcesController.settingsKey,
      const IncomeSources({IncomeSource.salary}).toJson(),
    );

    final opening = eat(2026, 8, 1, 0);
    final accounts = DriftAccountsRepository(db);
    bank = await accounts.accountForInstitution(
      'equity',
      name: 'Equity Bank',
      type: AccountType.bank,
      openingDate: opening,
      currency: 'KES',
    );
    mpesa = await accounts.accountForInstitution(
      'mpesa',
      name: 'M-Pesa',
      type: AccountType.mpesa,
      openingDate: opening,
      currency: 'KES',
    );
    fund = await accounts.add(
      AccountsCompanion.insert(
        name: 'Money market fund',
        type: AccountType.moneyMarket,
        openingDate: opening,
      ),
    );
    await accounts.setOpening(bank, kes(42000), opening);
    await accounts.setOpening(mpesa, kes(9000), opening);
    await accounts.setOpening(fund, kes(36000), opening);

    // The plan: a salary on the 25th, bills, debts, savings and a budget
    // for every day.
    final plan = DriftPlanRepository(db);
    Future<void> line(String name, String key, int shillings, int day) async =>
        plan.saveRecurring(
          name: name,
          categoryId: await _category(key),
          amountMinor: kes(shillings),
          frequency: RecurrenceFrequency.monthly,
          startDate: CalendarDate(2026, 8, day),
        );
    await line('Salary', 'salary', 110000, 25);
    await line('Rent', 'rent', 25000, 5);
    await line('School fees', 'school_fees', 15000, 10);
    await line('Home internet', 'utilities', 3000, 11);
    await line('KPLC tokens', 'utilities', 2500, 20);
    await line('Tax on side income', 'tax', 4000, 9);
    await line('Bank loan', 'loan_repayment', 8000, 28);
    await line('Family loan', 'loan_repayment', 3000, 28);
    await line('Emergency fund', 'savings', 8000, 26);
    await line('Food and household', 'groceries', 18000, 1);
    await line('Transport', 'transport', 6000, 1);
    await line('Eating out', 'eating_out', 4000, 1);
    await line('Airtime and data', 'airtime_data', 1000, 1);
    await line('Going out', 'lifestyle', 3000, 1);

    // Debts: a bank loan, a family loan and a salary advance now cleared.
    final debts = DriftDebtsRepository(db);
    bankLoan = await debts.add(
      DebtsCompanion.insert(
        lender: 'Bank loan',
        type: DebtType.bankLoan,
        startingBalanceMinor: kes(120000),
        annualRateBasisPoints: const Value(1300),
        minimumPaymentMinor: Value(kes(8000)),
        plannedPaymentMinor: Value(kes(8000)),
      ),
    );
    await debts.confirmBalance(bankLoan, kes(98300), eat(2026, 9, 1, 0));
    familyLoan = await debts.add(
      DebtsCompanion.insert(
        lender: 'Grace Wanjiru',
        type: DebtType.family,
        startingBalanceMinor: kes(30000),
        minimumPaymentMinor: Value(kes(3000)),
        plannedPaymentMinor: Value(kes(3000)),
        isFormal: const Value(false),
      ),
    );
    await debts.confirmBalance(familyLoan, kes(27000), eat(2026, 9, 1, 0));
    await debts.add(
      DebtsCompanion.insert(
        lender: 'Salary advance',
        type: DebtType.salaryAdvance,
        startingBalanceMinor: kes(10000),
        balanceMinor: Value(kes(0)),
        balanceAsOf: Value(eat(2026, 8, 30, 0)),
      ),
    );

    final goals = DriftGoalsRepository(db);
    await goals.add(
      name: 'Emergency fund',
      targetMinor: kes(150000),
      savedMinor: kes(60000),
      targetDate: CalendarDate(2027, 9, 30),
    );
    await goals.add(
      name: 'New laptop',
      targetMinor: kes(90000),
      savedMinor: kes(36000),
      targetDate: CalendarDate(2027, 3, 31),
    );
    await DriftLendingRepository(db).add(
      person: 'Peter Kamau',
      amountMinor: kes(2000),
      lentOn: CalendarDate(2026, 11, 2),
      dueDate: CalendarDate(2026, 11, 30),
    );

    // Shorter names, as someone may rename them.
    for (final (key, name) in [
      ('groceries', 'Food'),
      ('rent', 'Rent'),
      ('school_fees', 'School fees'),
      ('utilities', 'Utilities'),
      ('lifestyle', 'Going out'),
      ('loan_repayment', 'Debt payments'),
    ]) {
      await (db.update(db.categories)..where((c) => c.key.equals(key))).write(
        CategoriesCompanion(name: Value(name)),
      );
    }

    await _history();
    await _roundToday();
  }

  /// One more food shop yesterday, sized so today's safe-to-spend and the
  /// weekend amount come out in round tens of shillings.
  Future<void> _roundToday() async {
    final today = CalendarDate.local(_now);
    final month = today.yearMonth;
    final budget = await DriftPlanRepository(db).dayToDayBudgetMinor(month);
    final entries = await DriftTransactionsRepository(db).ledgerEntries(
      from: today.addDays(-40).startInstant,
      to: today.addDays(1).startInstant,
    );
    var weekday = 0;
    var weekend = 0;
    var before = 0;
    for (final e in entries) {
      final amount = dayToDaySpendOf(e);
      final d = e.date;
      if (!d.isBefore(today.addDays(-28)) && d.isBefore(today)) {
        d.isWeekend ? weekend += amount : weekday += amount;
      }
      if (month.contains(d) && d.isBefore(today)) before += amount;
    }
    var weekdays = 0;
    var weekends = 0;
    for (var d = today; month.contains(d); d = d.addDays(1)) {
      d.isWeekend ? weekends++ : weekdays++;
    }
    for (var a = 0; a < kes(3000); a += 100) {
      final denominator = (weekday + a) * 8;
      var w = (weekend * 2000 + denominator ~/ 2) ~/ denominator;
      w = w.clamp(minWeekendWeightPercent, maxWeekendWeightPercent);
      final left = budget - before - a;
      final shares = weekdays * 100 + weekends * w;
      final day = left * 100 ~/ shares;
      final end = left * w ~/ shares;
      if (left * 100 % shares == 0 &&
          left * w % shares == 0 &&
          day % 1000 == 0 &&
          end % 1000 == 0 &&
          a >= kes(600)) {
        await tx(
          mpesa,
          eat(2026, 11, 18, 18, 40),
          a ~/ 100,
          inflow: false,
          name: 'Green Basket Grocers',
          category: 'groceries',
          kind: TransactionKind.till,
        );
        return;
      }
    }
  }

  Future<void> _history() async {
    final transfers = <TransferPair>[];
    Future<void> toMpesa(DateTime at, int shillings) async {
      final out = await tx(
        bank,
        at,
        shillings,
        inflow: false,
        name: 'M-Pesa',
        kind: TransactionKind.bank,
      );
      final inn = await tx(
        mpesa,
        at.add(const Duration(minutes: 1)),
        shillings,
        inflow: true,
        name: 'Equity Bank',
      );
      transfers.add(TransferPair(out, inn));
    }

    // Each month's salary, bills and set-asides, up to today.
    for (final m in [8, 9, 10, 11]) {
      Future<void> when(int day, Future<void> Function(DateTime) f) async {
        final at = eat(2026, m, day, 10);
        if (at.isBefore(_now)) await f(at);
      }

      await when(
        5,
        (at) => tx(
          bank,
          at,
          25000,
          inflow: false,
          name: 'Achieng Otieno',
          category: 'rent',
          kind: TransactionKind.bank,
        ),
      );
      await when(
        9,
        (at) => tx(
          mpesa,
          at,
          4000,
          inflow: false,
          name: 'KRA',
          category: 'tax',
          kind: TransactionKind.paybill,
        ),
      );
      await when(
        10,
        (at) => tx(
          bank,
          at,
          15000,
          inflow: false,
          name: 'Hillside School',
          category: 'school_fees',
          kind: TransactionKind.bank,
        ),
      );
      await when(
        11,
        (at) => tx(
          mpesa,
          at,
          3000,
          inflow: false,
          name: 'Home internet',
          category: 'utilities',
          kind: TransactionKind.paybill,
        ),
      );
      await when(
        20,
        (at) => tx(
          mpesa,
          at,
          2500,
          inflow: false,
          name: 'KPLC tokens',
          category: 'utilities',
          kind: TransactionKind.paybill,
        ),
      );
      await when(25, (at) async {
        await tx(
          bank,
          at.subtract(const Duration(hours: 3)),
          110000,
          inflow: true,
          name: 'Lakeview Consulting',
          category: 'salary',
          kind: TransactionKind.bank,
        );
        await toMpesa(at, 46000);
      });
      await when(26, (at) async {
        await tx(
          bank,
          at,
          8000,
          inflow: false,
          name: 'Money market fund',
          category: 'savings',
          kind: TransactionKind.bank,
        );
        await tx(
          fund,
          at,
          8000,
          inflow: true,
          name: 'Equity Bank',
          category: 'savings',
          kind: TransactionKind.deposit,
        );
      });
      await when(28, (at) async {
        await tx(
          bank,
          at,
          8000,
          inflow: false,
          name: 'Bank loan',
          category: 'loan_repayment',
          kind: TransactionKind.bank,
          debt: m >= 9 ? bankLoan : null,
        );
        await tx(
          mpesa,
          at,
          3000,
          inflow: false,
          name: 'Grace Wanjiru',
          category: 'loan_repayment',
          feeShillings: 33,
          debt: m >= 9 ? familyLoan : null,
        );
      });
    }

    // Side work now and then.
    await tx(
      mpesa,
      eat(2026, 9, 18, 16),
      5000,
      inflow: true,
      name: 'Hillcrest Designs',
      category: 'business_income',
    );
    await tx(
      mpesa,
      eat(2026, 10, 14, 16),
      4000,
      inflow: true,
      name: 'Hillcrest Designs',
      category: 'business_income',
    );
    await tx(
      mpesa,
      eat(2026, 11, 13, 16),
      6500,
      inflow: true,
      name: 'Hillcrest Designs',
      category: 'business_income',
    );

    // Every day's spending from M-Pesa, a little more on food in November.
    var n = 0;
    for (
      var day = CalendarDate(2026, 8, 1);
      day.isBefore(CalendarDate(2026, 11, 19));
      day = day.addDays(1)
    ) {
      n++;
      DateTime at(int h, [int m = 0]) =>
          eat(day.year, day.month, day.day, h, m);
      final november = day.month == 11;
      if (n % 3 == 0) {
        await tx(
          mpesa,
          at(18, 20),
          1150 + (n * 137) % 500 + (november ? 300 : 0),
          inflow: false,
          name: 'Green Basket Grocers',
          category: 'groceries',
          kind: TransactionKind.till,
        );
      }
      if (!day.isWeekend) {
        await tx(
          mpesa,
          at(7, 40),
          day.weekday == DateTime.monday ? 300 : 250,
          inflow: false,
          name: 'Matatu fare',
          category: 'transport',
          kind: TransactionKind.till,
        );
      }
      if (day.weekday == DateTime.tuesday ||
          day.weekday == DateTime.friday ||
          day.weekday == DateTime.saturday) {
        await tx(
          mpesa,
          at(13, 10),
          300 + (n * 53) % 150,
          inflow: false,
          name: 'Sunrise Cafe',
          category: 'eating_out',
          kind: TransactionKind.till,
        );
      }
      if (n % 4 == 0) {
        await tx(
          mpesa,
          at(8, 5),
          100,
          inflow: false,
          name: 'Airtime',
          category: 'airtime_data',
          kind: TransactionKind.airtime,
        );
      }
      if (day.weekday == DateTime.saturday) {
        await tx(
          mpesa,
          at(19, 30),
          550 + (n * 31) % 200,
          inflow: false,
          name: 'Weekend out',
          category: 'lifestyle',
          kind: TransactionKind.till,
        );
      }
    }

    // Fuliza: twice in October, three times so far in November.
    Future<void> fuliza(DateTime at, int shillings, {bool draw = true}) => tx(
      mpesa,
      at,
      shillings,
      inflow: draw,
      name: 'Fuliza M-Pesa',
      kind: draw ? TransactionKind.fulizaDraw : TransactionKind.fulizaRepayment,
    );
    await fuliza(eat(2026, 10, 2, 18), 600);
    await fuliza(eat(2026, 10, 7, 9), 625, draw: false);
    await fuliza(eat(2026, 10, 12, 18), 500);
    await fuliza(eat(2026, 10, 15, 9), 520, draw: false);
    await fuliza(eat(2026, 10, 20, 18), 700);
    await fuliza(eat(2026, 10, 25, 11), 730, draw: false);
    await fuliza(eat(2026, 11, 3, 18), 450);
    await fuliza(eat(2026, 11, 6, 9), 470, draw: false);
    await fuliza(eat(2026, 11, 14, 19), 700);
    await fuliza(eat(2026, 11, 16, 9), 735, draw: false);
    await fuliza(eat(2026, 11, 17, 20), 300);

    await DriftTransactionsRepository(db).saveTransferPairs(transfers);
  }
}

/// [screen] in the personal tab bar; over [root] when given.
Widget _shell(Widget screen, int tab, {Widget? root}) =>
    tabShell(screen, tabs: personalTabs, index: tab, root: root);

Future<void> _pump(WidgetTester tester, Widget home) async {
  final db = openTestDatabase();
  await tester.runAsync(() => _Person(db).seed());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => _now),
        deviceRegionProvider.overrideWithValue('KE'),
        activeSpaceProvider.overrideWithValue(Space.personal),
        ...appLockOverrides(),
      ],
      child: shotApp(home),
    ),
  );
  await settleFrames(tester);
  await tester.pumpAndSettle();
}

void main() {
  screenshot('home', (tester) async {
    await _pump(tester, _shell(const HomeScreen(), 0));
    await snap(tester);
  });

  screenshot('plan', (tester) async {
    await _pump(tester, _shell(const PlanScreen(), 2));
    await snap(tester);
  });

  screenshot('goals', (tester) async {
    await _pump(tester, _shell(const GoalsScreen(), 3));
    await snap(tester);
  });

  screenshot('debts', (tester) async {
    await _pump(
      tester,
      _shell(const DebtsScreen(), 3, root: const GoalsScreen()),
    );
    // Three steps along the what-if slider, scrolled into view first.
    await tester.dragUntilVisible(
      find.byType(Slider),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    final slider = tester.getRect(find.byType(Slider));
    await tester.tapAt(
      Offset(slider.left + 24 + (slider.width - 48) * 0.15, slider.center.dy),
    );
    await tester.pumpAndSettle();
    await snap(tester);
  });

  screenshot('insights', (tester) async {
    await _pump(tester, _shell(const InsightsScreen(), 4));
    await snap(tester);
  });
}
