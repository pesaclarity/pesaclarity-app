// The screens for two M-Pesa lines: what they say, what their buttons do,
// and that each fits at every text size the phone offers (an overflow
// reports a Flutter error, which fails the test). Made-up data only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/domain/accounts/mpesa_lines.dart';
import 'package:pesaclarity/src/features/accounts/application/mpesa_lines_providers.dart';
import 'package:pesaclarity/src/shared/widgets/amounts_hidden.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/mpesa_lines_seed.dart';
import '../helpers/test_app.dart';

Future<SeededLines> _pump(
  WidgetTester tester,
  Widget Function(SeededLines) home, {
  bool split = false,
  bool iphone = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final seeded = (await tester.runAsync(
    () => seedLines(split: split, iphone: iphone),
  ))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: linesOverrides(seeded),
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: AmountsHiddenScope(child: child!),
        ),
        home: home(seeded),
      ),
    ),
  );
  await settleFrames(tester);
  await tester.pumpAndSettle();
  return seeded;
}

/// Scrolls the open sheet to its main button, as a person would at larger
/// text.
Future<void> _toSheetButton(WidgetTester tester) async {
  final button = find.byKey(const Key('mpesa-lines-save'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  expect(button, findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<MpesaLines> _saved(SeededLines seeded) async => MpesaLines.fromJson(
  await DriftAppSettingsRepository(seeded.db).readJson(mpesaLinesKey),
);

void main() {
  testAppWidgets('My accounts offers the split; Not now hides it', (
    tester,
  ) async {
    final seeded = await _pump(tester, myAccounts);
    expect(find.text('Two M-Pesa lines on this phone'), findsOneWidget);
    expect(find.text('Split them'), findsOneWidget);
    // The lines row is within reach before the split too.
    await tester.scrollUntilVisible(find.text('M-Pesa lines'), 200);
    expect(find.text('M-Pesa lines'), findsOneWidget);
    expect(find.text('Name them, or give one to a business'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('lines-offer-later')),
      -200,
    );
    await tester.tap(find.byKey(const Key('lines-offer-later')));
    await tester.pumpAndSettle();
    expect(find.text('Two M-Pesa lines on this phone'), findsNothing);
    expect((await tester.runAsync(() => _saved(seeded)))!.offerHidden, isTrue);
    expect(find.text('M-Pesa lines'), findsOneWidget);
  });

  testAppWidgets('the split sheet names each line and offers Both', (
    tester,
  ) async {
    await _pump(tester, myAccounts);
    await tester.tap(find.byKey(const Key('lines-offer-split')));
    await tester.pumpAndSettle();

    expect(find.text('Two M-Pesa lines'), findsOneWidget);
    // Its slot, and the hint in its name field.
    expect(find.text('SIM 1'), findsWidgets);
    expect(find.text('Balance 12,500 · 268 messages'), findsOneWidget);
    expect(find.text('Balance 24,330 · 144 messages'), findsOneWidget);
    expect(find.text('Where its money goes'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('mpesa-line-space-2')));
    await tester.pumpAndSettle();
    expect(find.text('Green Basket Grocers'), findsWidgets);
    expect(find.text('Both'), findsOneWidget);
    expect(
      find.text(
        'Past messages are read again into the right line. Nothing leaves '
        'the phone.',
      ),
      findsOneWidget,
    );
  });

  testAppWidgets('after the split each line has its row, and the line in '
      'the business shows as one quiet row', (tester) async {
    await _pump(tester, myAccounts, split: true);
    expect(find.text('M-Pesa · My line'), findsOneWidget);
    expect(find.text('Messages from MPESA · SIM 1'), findsOneWidget);
    // Given to the business: not among Personal's accounts.
    expect(find.text('M-Pesa · Shop line'), findsNothing);
    expect(find.text('Shop line is in Green Basket Grocers'), findsOneWidget);
    expect(
      find.textContaining('M-Pesa lines are told apart by the SIM'),
      findsOneWidget,
    );
  });

  testAppWidgets('on iPhone the lines say their balance until named', (
    tester,
  ) async {
    await _pump(tester, myAccounts, split: true, iphone: true);
    expect(find.text('M-Pesa · Line 1'), findsOneWidget);
    expect(find.text('Messages from MPESA · balance 12,500'), findsOneWidget);
    expect(find.text('M-Pesa · Line 2'), findsOneWidget);
    expect(
      find.textContaining('told apart by the balance each message shows'),
      findsOneWidget,
    );
  });

  testAppWidgets('Home asks which line, and about a new SIM', (tester) async {
    await _pump(tester, homeRows, split: true, iphone: true);
    expect(find.text('Which line was this?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-which-line')));
    await tester.pumpAndSettle();
    expect(
      find.text('You paid SUNRISE CAFE 300 today at 13:20.'),
      findsOneWidget,
    );
    expect(find.text('Balance 24,330'), findsOneWidget);
    expect(find.text("Don't ask me again"), findsOneWidget);
  });

  testAppWidgets('"Is this the same line?" shows both balances', (
    tester,
  ) async {
    await _pump(tester, homeRows, split: true);
    expect(find.text('Is this the same line as My line?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-same-line')));
    await tester.pumpAndSettle();
    expect(find.text('Pesa Clarity has not seen this SIM before.'), findsOne);
    expect(find.text('My line, last balance'), findsOneWidget);
    expect(find.text('Today 10:42'), findsOneWidget);
    expect(find.text('This SIM, first balance'), findsOneWidget);
    expect(find.text('9,150'), findsOneWidget);
    expect(find.text('Same line'), findsOneWidget);
    expect(find.text('A new line'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    group('at ${scale}x text', () {
      testAppWidgets('the offer and the split sheet fit', (tester) async {
        await _pump(tester, myAccounts, textScale: scale);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('lines-offer-split')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('lines-offer-split')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _toSheetButton(tester);
      });

      testAppWidgets('My accounts after the split and its sheet fit', (
        tester,
      ) async {
        await _pump(tester, myAccounts, split: true, textScale: scale);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(const Key('mpesa-lines')),
          200,
        );
        await tester.ensureVisible(find.byKey(const Key('mpesa-lines')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('mpesa-lines')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // M-Pesa lines, then one line's sheet.
        await tester.tap(find.byKey(const Key('line-row-1')));
        await tester.pumpAndSettle();
        final save = find.byKey(const Key('line-save'));
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Save'), findsOneWidget);
      });

      testAppWidgets('the iPhone lines and "Which line was this?" fit', (
        tester,
      ) async {
        await _pump(
          tester,
          myAccounts,
          split: true,
          iphone: true,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        await _pump(
          tester,
          whichLine,
          split: true,
          iphone: true,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Which line was this?'), findsOneWidget);
      });

      testAppWidgets('the Home rows and "Is this the same line?" fit', (
        tester,
      ) async {
        await _pump(tester, homeRows, split: true, textScale: scale);
        expect(tester.takeException(), isNull);
        await _pump(tester, sameLine, split: true, textScale: scale);
        expect(tester.takeException(), isNull);
        expect(find.text('Same line'), findsOneWidget);
      });
    });
  }
}
