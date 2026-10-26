import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';
import 'package:pesaclarity/src/features/export/application/export_service.dart';
import 'package:pesaclarity/src/features/export/presentation/export_sheet.dart';
import 'package:pesaclarity/src/features/insights/presentation/tag_totals_card.dart';
import 'package:pesaclarity/src/features/payees/presentation/payees_screen.dart';
import 'package:pesaclarity/src/features/payees/presentation/transaction_sheet.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/test_app.dart';

class _Sharer implements FileSharer {
  final shared = <String>[];

  @override
  Future<void> share(
    File file, {
    required String mimeType,
    String? subject,
  }) async => shared.add(file.path);
}

final _brother = PayeeIdentifier.phone('0700 000 001')!;

Future<int> _addSpend(AppDatabase db, {int day = 20}) async {
  final account = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: DateTime.utc(2026),
        ),
      );
  final ledger = DriftTransactionsRepository(db);
  await ledger.add(
    TransactionsCompanion.insert(
      accountId: account,
      occurredAt: DateTime.utc(2026, 10, day - 1, 9),
      amountMinor: 20000,
      direction: TransactionDirection.outflow,
      kind: const Value(TransactionKind.sent),
      source: TransactionSource.sms,
      counterpartyKind: Value(_brother.kind),
      counterpartyValue: Value(_brother.value),
      counterpartyName: const Value('JOHN KAMAU'),
    ),
  );
  return ledger.add(
    TransactionsCompanion.insert(
      accountId: account,
      occurredAt: DateTime.utc(2026, 10, day, 9),
      amountMinor: 35000,
      direction: TransactionDirection.outflow,
      kind: const Value(TransactionKind.sent),
      source: TransactionSource.sms,
      counterpartyKind: Value(_brother.kind),
      counterpartyValue: Value(_brother.value),
      counterpartyName: const Value('JOHN KAMAU'),
      receiptNo: const Value('TJK0000001'),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db,
  Widget child, {
  FileSharer? sharer,
  Directory? cache,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 26, 6)),
        if (sharer != null) fileSharerProvider.overrideWithValue(sharer),
        if (cache != null)
          exportCacheDirectoryProvider.overrideWithValue(() async => cache),
      ],
      child: MaterialApp(theme: AppTheme.light, home: child),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

void main() {
  testAppWidgets('naming a payee from a transaction applies to all of them', (
    tester,
  ) async {
    final db = openTestDatabase();
    final id = (await tester.runAsync(() => _addSpend(db)))!;
    await _pump(
      tester,
      db,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showTransactionSheet(context, id),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await _settle(tester);

    expect(find.text('JOHN KAMAU'), findsOneWidget);
    expect(find.text('-KES 350'), findsOneWidget);
    expect(find.text('Tap to name this payee'), findsOneWidget);
    expect(find.text('Uncategorised'), findsOneWidget);

    await tester.tap(find.text('Tap to name this payee'));
    await _settle(tester);
    expect(find.text('Name this payee'), findsOneWidget);
    expect(
      find.text('Applies to every past and future payment to 0700000001.'),
      findsOneWidget,
    );
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'John');
    await tester.tap(find.text('Family'));
    await tester.pump();
    await tester.tap(find.text('Save payee'));
    await _settle(tester);

    expect(find.text('John'), findsOneWidget);
    expect(find.text('John · Family leak'), findsOneWidget);
    final linked = await tester.runAsync(
      () => (db.select(
        db.transactions,
      )..where((t) => t.payeeId.isNotNull())).get(),
    );
    expect(linked, hasLength(2));

    // Inline category creation from the transaction.
    await tester.tap(find.text('Category'));
    await _settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Find or add a category'),
      'Harambee',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add category'));
    await _settle(tester);
    expect(find.text('Harambee · Set for this transaction'), findsOneWidget);

    // Tags: add two, remove one.
    await tester.ensureVisible(find.widgetWithText(TextField, 'Add a tag'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Add a tag'),
      'Wedding',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Add a tag'),
      'reimbursable',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect(find.text('#wedding'), findsOneWidget);
    expect(find.text('#reimbursable'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove #reimbursable'));
    await _settle(tester);
    expect(find.widgetWithText(InputChip, '#reimbursable'), findsNothing);
    expect(find.widgetWithText(ActionChip, '#reimbursable'), findsOneWidget);
  });

  testAppWidgets('Payees lists numbers to name and exports in two taps', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _addSpend(db));
    final cache = Directory.systemTemp.createTempSync('payees_widget');
    addTearDown(() => cache.deleteSync(recursive: true));
    final sharer = _Sharer();
    await _pump(tester, db, const PayeesScreen(), sharer: sharer, cache: cache);
    await _settle(tester);

    expect(find.text('JOHN KAMAU'), findsOneWidget);
    expect(
      find.text('0700000001 · 2 transactions · KES 550 out'),
      findsOneWidget,
    );
    expect(find.text('Payees you name show here.'), findsOneWidget);

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(
      find.text('Made on this phone. You choose where it goes.'),
      findsOneWidget,
    );
    await tester.tap(find.text('CSV'));
    for (var i = 0; i < 50 && sharer.shared.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(sharer.shared.single, endsWith('pesaclarity-payees-2026-10-26.csv'));
    expect(
      find.text('Made on this phone. You choose where it goes.'),
      findsNothing,
    );
  });

  testAppWidgets('Insights shows tag totals for the month', (tester) async {
    final db = openTestDatabase();
    final id = (await tester.runAsync(() => _addSpend(db)))!;
    await tester.runAsync(() async {
      final tag = await db
          .into(db.tags)
          .insert(TagsCompanion.insert(name: 'roadtrip'));
      await db
          .into(db.transactionTags)
          .insert(
            TransactionTagsCompanion.insert(transactionId: id, tagId: tag),
          );
    });
    await _pump(tester, db, const Scaffold(body: TagTotalsSection()));
    await _settle(tester);
    expect(find.text('Tags in October'), findsOneWidget);
    expect(find.text('#roadtrip'), findsOneWidget);
    expect(find.text('350'), findsOneWidget);
    expect(find.text('1 transaction'), findsOneWidget);
    expect(find.byTooltip('Export tags'), findsOneWidget);
  });

  testAppWidgets('the export sheet offers the full workbook', (tester) async {
    final db = openTestDatabase();
    await _pump(
      tester,
      db,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showExportSheet(context, const FullWorkbookExport()),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Pesa Clarity workbook'), findsOneWidget);
    expect(find.text('One CSV file per table, zipped'), findsOneWidget);
    expect(find.text('Every table and tag, one sheet each'), findsOneWidget);
    expect(find.text('Ready to print or send'), findsOneWidget);
  });
}
