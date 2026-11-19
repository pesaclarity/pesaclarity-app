// The sheets and dialogs most screens open, for the accessibility check
// (tool/accessibility.sh): each at every text size, in light and dark. Not
// marketing screenshots, so tool/screenshots.sh skips them.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/activity/presentation/add_transaction_sheet.dart';
import 'package:pesaclarity/src/features/app_status/presentation/update_check_sheet.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/debts/presentation/debt_sheet.dart';
import 'package:pesaclarity/src/features/goals/presentation/goal_sheet.dart';
import 'package:pesaclarity/src/features/home/presentation/add_menu.dart';
import 'package:pesaclarity/src/features/lending/presentation/loan_sheet.dart';
import 'package:pesaclarity/src/features/plan/presentation/plan_item_sheet.dart';
import 'package:pesaclarity/src/features/sales/presentation/records_sheets.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/features/spaces/presentation/spaces_sheet.dart';
import 'package:pesaclarity/src/features/stock/presentation/item_sheet.dart';
import 'package:pesaclarity/src/shared/adaptive/adaptive.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';

final _now = eat(2026, 11, 19, 9, 30);
final _today = CalendarDate.local(_now);

/// Registers [name]: an empty screen that opens what [open] shows, then
/// checks it. Only in the accessibility check.
void _sheet(
  String name,
  void Function(BuildContext context) open, {
  Space space = Space.personal,
}) {
  if (!checkAccessibility) return;
  screenshot(name, (tester) async {
    final db = openTestDatabase();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          personalDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => _now),
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
  _sheet('plan-item', (c) => showPlanItemSheet(c, month: _today.yearMonth));
  _sheet('spaces-sheet', showSpaces);
  _sheet('update-check-sheet', showUpdateCheckSheet);
  _sheet('item-sheet', showItemSheet, space: _shop);
  _sheet('bought-sheet', showBoughtSheet, space: _shop);
  _sheet(
    'confirm-dialog',
    (c) => confirmDelete(
      c,
      title: 'Delete Rent?',
      body: 'It goes from this month and every month after.',
    ),
  );
}
