import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/debts/next_due.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/debts/presentation/debts_screen.dart';
import 'package:pesaclarity/src/features/debts/presentation/due_line.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';
import 'package:pesaclarity/src/theme/pesa_colors.dart';

import '../helpers/app_fonts.dart';
import '../helpers/goals_harness.dart' show settle;

// Synthetic loan: invented lender, amounts and dates.

/// 08:00 EAT on [day] (of November or December 2026).
DateTime _at(int month, int day) => DateTime.utc(2026, month, day, 5);

void main() {
  late AppDatabase db;

  // The app's own fonts, so text takes the widths it takes on a phone.
  setUpAll(loadAppFonts);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// A KCB loan of 20,000 with 12,000 left after a 2,500 repayment read
  /// from KCB's message on Fri 20 Nov, next due Sat 5 Dec.
  Future<int> kcbLoan({bool fromMessage = true}) async {
    final account = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'KCB',
            type: AccountType.bank,
            openingDate: DateTime.utc(2026),
            institutionId: const Value('kcb'),
          ),
        );
    final debt = await db
        .into(db.debts)
        .insert(
          DebtsCompanion.insert(
            lender: 'KCB loan',
            type: DebtType.bankLoan,
            startingBalanceMinor: 2000000,
            minimumPaymentMinor: const Value(250000),
            annualRateBasisPoints: const Value(1300),
          ),
        );
    final paidAt = DateTime.utc(2026, 11, 20, 6, 14);
    final repayment = await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: account,
            occurredAt: paidAt,
            amountMinor: 250000,
            direction: TransactionDirection.outflow,
            kind: const Value(TransactionKind.loanRepayment),
            source: TransactionSource.sms,
            debtId: Value(debt),
          ),
        );
    await (db.update(db.debts)..where((d) => d.id.equals(debt))).write(
      DebtsCompanion(
        balanceMinor: const Value(1200000),
        balanceAsOf: Value(paidAt.add(const Duration(seconds: 1))),
        nextDueDay: const Value(20261205),
        nextDueSetAt: Value(paidAt),
        nextDueTransactionId: Value(fromMessage ? repayment : null),
      ),
    );
    return debt;
  }

  /// Pumps Debts on [now], on a 411 × 914 phone unless [narrow], when on a
  /// 390 × 844 one, as the accessibility check draws.
  Future<void> pump(
    WidgetTester tester,
    DateTime now, {
    ThemeData? theme,
    bool narrow = false,
  }) async {
    tester.view
      ..physicalSize = narrow ? const Size(1170, 2532) : const Size(1080, 2400)
      ..devicePixelRatio = narrow ? 3 : 2.625;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: const DebtsScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  Text lineText(WidgetTester tester) => tester.widget<Text>(
    find.descendant(of: find.byType(DueLine), matching: find.byType(Text)),
  );

  BuildContext lineContext(WidgetTester tester) =>
      tester.element(find.byType(DueLine));

  group('the row', () {
    testWidgets('says the next instalment while there is time', (tester) async {
      await kcbLoan();
      await pump(tester, _at(11, 21));
      expect(find.text('Next KES 2,500 due 5 Dec'), findsOneWidget);
      expect(find.byIcon(Icons.event_outlined), findsOneWidget);
      // The usual caption stays.
      expect(find.textContaining('13% p.a. · 2,500 a month'), findsOneWidget);
      expect(
        lineText(tester).style!.color,
        Theme.of(lineContext(tester)).colorScheme.onSurface,
      );
    });

    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      testWidgets('turns amber within three days ($name)', (tester) async {
        await kcbLoan();
        await pump(tester, _at(12, 3), theme: theme);
        expect(
          find.text('Next KES 2,500 due in 2 days, 5 Dec'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.schedule), findsOneWidget);
        expect(
          lineText(tester).style!.color,
          PesaColors.of(lineContext(tester)).warning,
        );
      });

      testWidgets('turns red once late with no repayment ($name)', (
        tester,
      ) async {
        await kcbLoan();
        await pump(tester, _at(12, 8), theme: theme);
        expect(
          find.text('KES 2,500 was due 5 Dec · 3 days late'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(
          lineText(tester).style!.color,
          Theme.of(lineContext(tester)).colorScheme.error,
        );
      });
    }

    testWidgets('says today on the day', (tester) async {
      await kcbLoan();
      await pump(tester, _at(12, 5));
      expect(find.text('Next KES 2,500 due today'), findsOneWidget);
    });

    testWidgets('goes once a repayment comes in after the date', (
      tester,
    ) async {
      final debt = await kcbLoan();
      await db
          .into(db.loanPayments)
          .insert(
            LoanPaymentsCompanion.insert(
              debtId: Value(debt),
              paidOn: _at(12, 6),
              amountMinor: 250000,
            ),
          );
      await pump(tester, _at(12, 8));
      expect(find.byType(DueLine), findsNothing);
      expect(find.text('KCB loan'), findsOneWidget);
    });

    testWidgets('a debt with no due date has no line', (tester) async {
      await db
          .into(db.debts)
          .insert(
            DebtsCompanion.insert(
              lender: 'Test Sacco',
              type: DebtType.saccoLoan,
              startingBalanceMinor: 500000,
            ),
          );
      await pump(tester, _at(11, 21));
      expect(find.byType(DueLine), findsNothing);
    });
  });

  group('the loan', () {
    testWidgets('opens on its balance, next payment and due date', (
      tester,
    ) async {
      await kcbLoan();
      await pump(tester, _at(11, 21));
      await tester.tap(find.text('KCB loan'));
      await settle(tester);

      expect(find.text('Outstanding balance'), findsOneWidget);
      expect(find.text('KES 12,000'), findsOneWidget);
      expect(
        find.text('40% paid · 13% p.a. · cleared Mar 2027'),
        findsOneWidget,
      );
      expect(find.text('Next payment'), findsOneWidget);
      expect(find.text('KES 2,500'), findsNWidgets(2));
      expect(find.text('Sat, 5 Dec 2026'), findsOneWidget);
      expect(find.text('in 14 days'), findsOneWidget);
      expect(find.text('Last payment'), findsOneWidget);
      expect(find.text('Fri, 20 Nov'), findsOneWidget);
      expect(
        find.text('From your KCB messages · 20 Nov', findRichText: true),
        findsOneWidget,
      );
      // Message text is never kept, so there is none to quote.
      expect(find.text('The message'), findsNothing);
    });

    testWidgets('keeps amounts whole and at the end of their line', (
      tester,
    ) async {
      await kcbLoan();
      await pump(tester, _at(11, 21), narrow: true);
      await tester.tap(find.text('KCB loan'));
      await settle(tester);
      // As in the approved design: each value at the card's end.
      final card = tester.getRect(
        find.ancestor(
          of: find.text('Next payment'),
          matching: find.byType(Card),
        ),
      );
      for (final value in [
        find.text('KES 2,500').first,
        find.text('Sat, 5 Dec 2026'),
      ]) {
        expect(tester.getRect(value).right, closeTo(card.right - 16, 1));
      }

      // At twice the text size the amounts and the date stay on one line,
      // the date under its label, still at the end.
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await settle(tester);
      final date = tester.getRect(find.text('Sat, 5 Dec 2026'));
      expect(date.top, greaterThan(tester.getRect(find.text('Due')).bottom));
      expect(date.right, closeTo(card.right - 16, 1));
      for (final value in [
        find.text('KES 12,000'),
        ...find
            .text('KES 2,500')
            .evaluate()
            .map((e) => find.byWidget(e.widget)),
        find.text('Sat, 5 Dec 2026'),
      ]) {
        final text = tester.renderObject<RenderParagraph>(
          find.descendant(of: value, matching: find.byType(RichText)),
        );
        expect(
          text.size.width + 0.5,
          greaterThanOrEqualTo(text.getMaxIntrinsicWidth(double.infinity)),
          reason: '${text.text.toPlainText()} is on one line',
        );
      }
    });

    testWidgets('a typed date says so', (tester) async {
      await kcbLoan(fromMessage: false);
      await pump(tester, _at(12, 8));
      await tester.tap(find.text('KCB loan'));
      await settle(tester);
      expect(find.text('3 days late'), findsOneWidget);
      expect(
        find.text('Due date set by you', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('edits the due date from Edit', (tester) async {
      final debt = await kcbLoan();
      await pump(tester, _at(11, 21));
      await tester.tap(find.text('KCB loan'));
      await settle(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await settle(tester);

      expect(find.text('Next due (optional)'), findsOneWidget);
      expect(find.text('Sat 5 Dec'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear date'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      final row = await (db.select(
        db.debts,
      )..where((d) => d.id.equals(debt))).getSingle();
      expect(row.nextDueDay, isNull);
      expect(find.text('Sat, 5 Dec 2026'), findsNothing);
      expect(fromDayKey(20261205), CalendarDate(2026, 12, 5));
    });
  });
}
