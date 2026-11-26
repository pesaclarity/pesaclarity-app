// The sheets and dialogs most screens open, for the accessibility check
// (tool/accessibility.sh): each at every text size, in light and dark. Not
// marketing screenshots, so tool/screenshots.sh skips them.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/lending/loan_link.dart';
import 'package:pesaclarity/src/domain/savings/savings_account.dart';
import 'package:pesaclarity/src/domain/savings/savings_product.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/activity/presentation/add_transaction_sheet.dart';
import 'package:pesaclarity/src/features/app_status/presentation/update_check_sheet.dart';
import 'package:pesaclarity/src/features/crash_reports/domain/crash_report.dart';
import 'package:pesaclarity/src/features/crash_reports/presentation/crash_choice_sheet.dart';
import 'package:pesaclarity/src/features/crash_reports/presentation/crash_report_sheet.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/debts/presentation/debt_sheet.dart';
import 'package:pesaclarity/src/features/goals/presentation/goal_sheet.dart';
import 'package:pesaclarity/src/features/home/presentation/add_menu.dart';
import 'package:pesaclarity/src/features/lending/presentation/loan_sheet.dart';
import 'package:pesaclarity/src/features/payees/presentation/category_picker.dart';
import 'package:pesaclarity/src/features/plan/presentation/plan_item_sheet.dart';
import 'package:pesaclarity/src/features/sales/presentation/records_sheets.dart';
import 'package:pesaclarity/src/features/savings/presentation/add_savings_sheet.dart';
import 'package:pesaclarity/src/features/savings/presentation/savings_pocket_sheet.dart';
import 'package:pesaclarity/src/features/savings/presentation/update_savings_balance_sheet.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/features/spaces/presentation/spaces_sheet.dart';
import 'package:pesaclarity/src/features/stock/presentation/item_sheet.dart';
import 'package:pesaclarity/src/shared/adaptive/adaptive.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';
import 'savings_records.dart';

final _now = eat(2026, 11, 19, 9, 30);
final _today = CalendarDate.local(_now);

/// Registers [name]: an empty screen that opens what [open] shows, then
/// checks it. Only in the accessibility check. [seed] fills the records
/// first, for a sheet that shows them.
void _sheet(
  String name,
  void Function(BuildContext context) open, {
  Space space = Space.personal,
  Future<void> Function(AppDatabase db)? seed,
}) {
  if (!checkAccessibility) return;
  screenshot(name, (tester) async {
    final db = openTestDatabase();
    if (seed != null) await tester.runAsync(() => seed(db));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          personalDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(
            () => seed == null ? _now : savingsNow,
          ),
          deviceRegionProvider.overrideWithValue('KE'),
          activeSpaceProvider.overrideWithValue(space),
          ...appLockOverrides(),
        ],
        child: shotApp(
          Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => open(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleFrames(tester);
    await tester.tap(find.text('Open'));
    await settleFrames(tester);
    await tester.pumpAndSettle();
    await snap(tester);
  });
}

const _shop = Space(
  id: 'shop1',
  name: 'Green Basket',
  kind: SpaceKind.business,
);

void main() {
  _sheet('add-menu', showAddMenu);
  _sheet('add-menu-business', (c) => showAddMenu(c, business: true));
  _sheet('add-transaction', showAddTransactionSheet);
  _sheet('goal-sheet', (c) => showGoalSheet(c, today: _today));
  _sheet('debt-sheet', (c) => showDebtSheet(c, today: _today));
  _sheet('loan-sheet', (c) => showLoanSheet(c, today: _today));
  // "I lent this" from a transaction: the same sheet, as "I lent".
  _sheet(
    'loan-sheet-from-transaction',
    (c) => showLoanSheet(
      c,
      today: _today,
      fromTransaction: LentFromTransaction(
        transactionId: 1,
        amountMinor: 250000,
        on: _today,
        person: 'Test Grace',
      ),
    ),
  );
  // The category picker with Lent and borrowed's answers, for money out
  // and money in.
  _sheet(
    'category-picker-lent',
    (c) => pickCategory(
      c,
      loanLinks: LoanLink.forDirection(outflow: true),
      selectedLink: LoanLink.lent,
    ),
  );
  _sheet(
    'category-picker-borrowed',
    (c) => pickCategory(c, loanLinks: LoanLink.forDirection(outflow: false)),
  );
  _sheet('plan-item', (c) => showPlanItemSheet(c, month: _today.yearMonth));
  _sheet('spaces-sheet', showSpaces);
  _sheet('update-check-sheet', showUpdateCheckSheet);
  _sheet('crash-choice-sheet', showCrashChoiceSheet);
  _sheet(
    'crash-report-sheet',
    (c) => showCrashReportSheet(c, const [
      CrashReport(
        app: '0.5.2',
        buildNumber: 412,
        build: 'play',
        os: 'Android 13',
        cpu: 'arm64',
        error: 'TypeError',
        buildId: 'b6f1c4e09a2d7f35',
        stack: ['#00 pc 0x2f4b3c', '#01 pc 0x2f49e0'],
      ),
    ]),
  );
  _sheet('item-sheet', showItemSheet, space: _shop);
  _sheet('bought-sheet', showBoughtSheet, space: _shop);
  _sheet(
    'add-savings-sheet',
    (c) => showAddSavingsSheet(c, chumz),
    seed: (db) => SavingsRecords(db).seed(),
  );
  late SavingsAccountSummary chumzAccount;
  _sheet(
    'update-savings-balance',
    (c) => showUpdateSavingsBalanceSheet(c, chumzAccount),
    seed: (db) async {
      final records = SavingsRecords(db);
      final id = await records.addChumz(await records.seed(), balances: false);
      chumzAccount = await records.account(id);
    },
  );
  _sheet(
    'savings-pocket-sheet',
    (c) => showSavingsPocketSheet(
      c,
      SavingsPocket(
        id: 1,
        accountId: 1,
        code: 'CH12345',
        name: 'Christmas',
        lockedUntil: CalendarDate(2026, 12, 15),
      ),
    ),
  );
  _sheet(
    'confirm-dialog',
    (c) => confirmDelete(
      c,
      title: 'Delete Rent?',
      body: 'It goes from this month and every month after.',
    ),
  );
}
