import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/features/review/presentation/review_message_screen.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';
import 'balances_harness.dart';

/// M-Pesa said 140 on Sunday 8 November at 13:07; 150 came in from
/// someone at 17:22 and M-Pesa then said 150, so 140 is not explained.
/// With [unread], a message paying out 140 waits in Messages to check.
Future<int> seedGap(AppDatabase db, {required bool unread}) async {
  final mpesa = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: eat(2026, 11, 1, 0),
          institutionId: const Value('mpesa'),
        ),
      );
  await DriftTransactionsRepository(db).addNew([
    TransactionsCompanion.insert(
      accountId: mpesa,
      occurredAt: eat(2026, 11, 8, 13, 7),
      amountMinor: kes(60),
      direction: TransactionDirection.outflow,
      kind: const Value(TransactionKind.till),
      counterpartyName: const Value('EXAMPLE KIOSK'),
      source: TransactionSource.sms,
      dedupeKey: const Value('gap-1'),
      receiptNo: const Value('TST0000301'),
      balanceAfterMinor: Value(kes(140)),
    ),
    TransactionsCompanion.insert(
      accountId: mpesa,
      occurredAt: eat(2026, 11, 8, 17, 22),
      amountMinor: kes(150),
      direction: TransactionDirection.inflow,
      kind: const Value(TransactionKind.received),
      counterpartyName: const Value('EXAMPLE PERSON'),
      source: TransactionSource.sms,
      dedupeKey: const Value('gap-2'),
      receiptNo: const Value('TST0000302'),
      balanceAfterMinor: Value(kes(150)),
    ),
  ]);
  if (unread) {
    await db
        .into(db.reviewItems)
        .insert(
          ReviewItemsCompanion.insert(
            institutionId: 'mpesa',
            sender: 'MPESA',
            receivedAt: eat(2026, 11, 8, 16),
            messageHash: 'gap-review-1',
            body: const Value(
              'Dear Customer, KES 140.00 has been paid to EXAMPLE SHOP on '
              '8/11/26 at 16:00. Ref TST0000303.',
            ),
            reason: 'no rule matched',
          ),
        );
  }
  return mpesa;
}

Future<void> openGap(WidgetTester tester) async {
  final card = find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('gap-'),
  );
  await tester.tap(card.first);
  await settle(tester);
}

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());

  Future<List<TransactionRecord>> rows(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.transactions).get()))!;

  testAppWidgets('the waiting 140 message is the likely missing one', (
    tester,
  ) async {
    await tester.runAsync(() => seedGap(db, unread: true));
    await pumpBalances(tester, db, AppRoutes.balanceCheck);
    expect(find.text('1 thing to fix'), findsOneWidget);
    await openGap(tester);

    expect(find.text('LIKELY THE MISSING ONE'), findsOneWidget);
    expect(find.textContaining('exactly the gap'), findsWidgets);
    expect(find.text('WAITING IN MESSAGES TO CHECK'), findsOneWidget);
    expect(find.text('EVERYTHING ON M-PESA'), findsOneWidget);
    expect(find.text("Add what's missing"), findsOneWidget);
    expect(find.text("It's just a correction"), findsOneWidget);
    expect(find.byKey(const Key('where-it-went-gap')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('gap-lead-action')),
        matching: find.text('Check this message'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('gap-lead-action')));
    await settle(tester);
    expect(find.byType(ReviewMessageScreen), findsOneWidget);
  });

  testAppWidgets('without it, Fuliza leads and Add what\'s missing files '
      'the 140 as spending', (tester) async {
    final mpesa = (await tester.runAsync(() => seedGap(db, unread: false)))!;
    await pumpBalances(tester, db, AppRoutes.balanceCheck);
    await openGap(tester);

    expect(find.text('WAITING IN MESSAGES TO CHECK'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('gap-lead-action')),
        matching: find.text('It went to Fuliza'),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const Key('gap-add-missing')));
    await tester.tap(find.byKey(const Key('gap-add-missing')));
    await settle(tester);
    expect(find.text("Add what's missing"), findsOneWidget);
    final amount = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('add-missing-amount')),
        matching: find.byType(TextField),
      ),
    );
    expect(amount.controller!.text, '140');

    await tester.tap(find.byKey(const Key('add-missing-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-missing-kind-airtime')).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add-missing-who')), 'Bonga');
    await tester.tap(find.byKey(const Key('add-missing-save')));
    await settle(tester);

    final added = (await rows(tester))
        .singleWhere((r) => r.source == TransactionSource.manual);
    expect(added.accountId, mpesa);
    expect(added.kind, TransactionKind.airtime);
    expect(added.direction, TransactionDirection.outflow);
    expect(added.amountMinor, kes(140));
    expect(added.categoryOverrideId, isNotNull);
    expect(added.occurredAt.isAfter(eat(2026, 11, 8, 13, 7)), isTrue);
    expect(added.occurredAt.isBefore(eat(2026, 11, 8, 17, 22)), isTrue);
    expect(find.text('Everything adds up'), findsOneWidget);
  });

  testAppWidgets('It went to Fuliza records a repayment that closes it', (
    tester,
  ) async {
    await tester.runAsync(() => seedGap(db, unread: false));
    await pumpBalances(tester, db, AppRoutes.balanceCheck);
    await openGap(tester);
    await tester.tap(find.byKey(const Key('gap-lead-action')));
    await settle(tester);
    final repaid = (await rows(tester))
        .singleWhere((r) => r.kind == TransactionKind.fulizaRepayment);
    expect(repaid.amountMinor, kes(140));
    expect(find.text('Everything adds up'), findsOneWidget);
  });

  testAppWidgets("It's just a correction stays as the last way out", (
    tester,
  ) async {
    await tester.runAsync(() => seedGap(db, unread: false));
    await pumpBalances(tester, db, AppRoutes.balanceCheck);
    await openGap(tester);
    await tester.ensureVisible(find.byKey(const Key('gap-correction')));
    await tester.tap(find.byKey(const Key('gap-correction')));
    await settle(tester);
    expect(
      (await rows(tester)).where((r) => r.kind == TransactionKind.correction),
      hasLength(1),
    );
  });
}
