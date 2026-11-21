// Loans with a next due date, for the accessibility check
// (tool/accessibility.sh): the Debts list with one loan in each state of its
// due line, then a loan's details, each at every text size, in light and
// dark. Not marketing screenshots, so tool/screenshots.sh skips them.
// Made-up lenders, amounts and dates.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/debts/next_due.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/debts/presentation/debts_screen.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';

/// Saturday 21 November 2026, 09:30 in Nairobi.
final _now = eat(2026, 11, 21, 9, 30);

/// Three loans: one due in two weeks, read from KCB's message after
/// yesterday's repayment; one due in two days; one three days late.
Future<void> _seed(AppDatabase db) async {
  final kcb = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'KCB',
          type: AccountType.bank,
          openingDate: DateTime.utc(2026),
          institutionId: const Value('kcb'),
        ),
      );

  Future<void> loan(
    String lender, {
    required int startingMajor,
    required int leftMajor,
    required int minimumMajor,
    required int rateBasisPoints,
    required CalendarDate due,
    DateTime? repaidAt,
  }) async {
    final debt = await db
        .into(db.debts)
        .insert(
          DebtsCompanion.insert(
            lender: lender,
            type: DebtType.bankLoan,
            startingBalanceMinor: kes(startingMajor),
            minimumPaymentMinor: Value(kes(minimumMajor)),
            annualRateBasisPoints: Value(rateBasisPoints),
          ),
        );
    int? repayment;
    if (repaidAt != null) {
      repayment = await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: kcb,
              occurredAt: repaidAt,
              amountMinor: kes(minimumMajor),
              direction: TransactionDirection.outflow,
              kind: const Value(TransactionKind.loanRepayment),
              source: TransactionSource.sms,
              debtId: Value(debt),
            ),
          );
    }
    final asOf = repaidAt ?? eat(2026, 11, 1, 0);
    await (db.update(db.debts)..where((d) => d.id.equals(debt))).write(
      DebtsCompanion(
        balanceMinor: Value(kes(leftMajor)),
        balanceAsOf: Value(asOf.add(const Duration(seconds: 1))),
        nextDueDay: Value(dayKey(due)),
        nextDueSetAt: Value(asOf),
        nextDueTransactionId: Value(repayment),
      ),
    );
  }

  await loan(
    'KCB Salary Advance',
    startingMajor: 20000,
    leftMajor: 12000,
    minimumMajor: 2500,
    rateBasisPoints: 1300,
    due: CalendarDate(2026, 12, 5),
    repaidAt: eat(2026, 11, 20, 9, 14),
  );
  await loan(
    'Test Sacco loan',
    startingMajor: 30000,
    leftMajor: 21000,
    minimumMajor: 3000,
    rateBasisPoints: 1200,
    due: CalendarDate(2026, 11, 23),
  );
  await loan(
    'Test Bank loan',
    startingMajor: 8000,
    leftMajor: 6000,
    minimumMajor: 1500,
    rateBasisPoints: 1400,
    due: CalendarDate(2026, 11, 18),
  );
}

void main() {
  if (!checkAccessibility) return;
  screenshot('debts-due', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _seed(db));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          personalDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => _now),
          deviceRegionProvider.overrideWithValue('KE'),
          activeSpaceProvider.overrideWithValue(Space.personal),
          ...appLockOverrides(),
        ],
        child: shotApp(const DebtsScreen()),
      ),
    );
    await settleFrames(tester);
    await tester.pumpAndSettle();
    await snap(tester);

    final loan = find.text('KCB Salary Advance');
    await tester.ensureVisible(loan);
    await tester.pumpAndSettle();
    await tester.tap(loan);
    await settleFrames(tester);
    await tester.pumpAndSettle();
    await snap(tester, variant: 'loan-detail');
  });
}
