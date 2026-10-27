import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/features/reminders/data/reminder_notifications.dart';
import 'package:pesaclarity/src/features/subscriptions/presentation/subscriptions_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_reminders.dart';
import '../helpers/test_app.dart';

Future<void> _seed(AppDatabase db) async {
  final account = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: DateTime.utc(2026),
        ),
      );
  final payee = await db
      .into(db.payees)
      .insert(PayeesCompanion.insert(displayName: 'Example Streaming'));
  for (final (month, amount) in [(9, 250), (10, 300)]) {
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: account,
            occurredAt: eat(2026, month, 2),
            amountMinor: kes(amount),
            direction: TransactionDirection.outflow,
            kind: const Value(TransactionKind.paybill),
            payeeId: Value(payee),
            source: TransactionSource.manual,
          ),
        );
  }
}

void main() {
  late AppDatabase db;
  late FakeReminderNotifications notifications;

  setUp(() {
    db = openTestDatabase();
    notifications = FakeReminderNotifications();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 27, 9)),
          reminderNotificationsProvider.overrideWithValue(notifications),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const SubscriptionsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testAppWidgets('tracks a charge found in messages, with its price change', (
    tester,
  ) async {
    await tester.runAsync(() => _seed(db));
    await pump(tester);

    expect(find.text('FOUND IN YOUR MESSAGES'), findsOneWidget);
    expect(find.text('Example Streaming'), findsOneWidget);
    await tester.tap(find.text('Track it'));
    await tester.pumpAndSettle();

    expect(find.text('FOUND IN YOUR MESSAGES'), findsNothing);
    expect(find.text('1 active · every month'), findsOneWidget);
    expect(find.text('KES 300'), findsOneWidget);
    expect(find.text('Now 300, was 250 · 2 Nov'), findsOneWidget);
  });

  testAppWidgets('a one-off is not suggested again', (tester) async {
    await tester.runAsync(() => _seed(db));
    await pump(tester);

    await tester.tap(find.text('One-off'));
    await tester.pumpAndSettle();
    expect(find.text('FOUND IN YOUR MESSAGES'), findsNothing);
    expect(find.text('Nothing tracked yet'), findsOneWidget);
  });

  testAppWidgets('adds, edits and stops tracking one by hand', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Add a subscription'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('subscription-name')), 'Gym');
    await tester.enterText(
      find.byKey(const Key('subscription-amount')),
      '3,000',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Gym'), findsOneWidget);
    expect(find.text('KES 3,000'), findsOneWidget);

    await tester.tap(find.text('Gym'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop tracking'));
    await tester.pumpAndSettle();
    expect(find.text('Gym'), findsNothing);
  });

  testAppWidgets('the reminder switch turns on charge reminders', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('subscription-reminders')));
    await tester.pumpAndSettle();
    expect(notifications.permissionRequests, 1);
    final row = await db.select(db.appSettings).get();
    expect(row.single.value, contains('"cardCharges":true'));
    expect(row.single.value, contains('"enabled":true'));
  });
}
