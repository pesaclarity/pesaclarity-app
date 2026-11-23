// M-Pesa lines with many lines: the list newest first with old lines
// folded, the quick setup, one line's sheet with its four choices, the
// delete and merge confirms, the screen after, and the quiet note on the
// first skipped message; each fits at every text size the phone offers (an
// overflow reports a Flutter error, which fails the test). Made-up data.
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
  Widget home, {
  bool after = false,
  bool iphone = false,
  double textScale = 1,
  Future<void> Function(SeededLines)? also,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final seeded = (await tester.runAsync(() async {
    final s = await seedManyLines(after: after, iphone: iphone);
    if (also != null) await also(s);
    return s;
  }))!;
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
        home: home,
      ),
    ),
  );
  await settleFrames(tester);
  await tester.pumpAndSettle();
  return seeded;
}

Future<MpesaLines> _saved(SeededLines seeded) async => MpesaLines.fromJson(
  await DriftAppSettingsRepository(seeded.db).readJson(mpesaLinesKey),
);

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testAppWidgets('M-Pesa lines: newest first, quick setup, old lines folded', (
    tester,
  ) async {
    await _pump(tester, manyLines());
    expect(
      find.text(
        '6 lines found on this phone, newest first. Tap one to name it, '
        'merge it or stop tracking it.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Keep my 2 most recent lines, set the rest aside'),
      findsOneWidget,
    );
    expect(
      find.text('My line and SIM 5 stay. 4 old lines stop being tracked.'),
      findsOneWidget,
    );
    expect(find.textContaining('Most recent'), findsOneWidget);
    expect(find.textContaining('2nd most recent'), findsOneWidget);
    expect(
      find.text(
        'Last message today · 412 messages\n'
        'Balance 12,500 · since 3 Feb 2024',
      ),
      findsOneWidget,
    );
    expect(find.text('Old lines (4)'), findsOneWidget);
    expect(find.text('No messages for over 90 days'), findsOneWidget);
    expect(find.byKey(const Key('line-row-4')), findsNothing);
    expect(
      find.text('A line used in the last 90 days stays up top.'),
      findsOneWidget,
    );
    await _tap(tester, 'lines-old');
    expect(find.byKey(const Key('line-row-4')), findsOneWidget);
    expect(
      find.text(
        'Last message 2 Jun 2026 · 38 messages\n'
        'Balance 1,020 · since 11 Jan 2026',
      ),
      findsOneWidget,
    );
  });

  testAppWidgets('the quick setup keeps the two most recent, then hides', (
    tester,
  ) async {
    final seeded = await _pump(tester, manyLines());
    await _tap(tester, 'lines-quick-setup');
    expect(find.text('Keep your 2 most recent lines?'), findsOneWidget);
    expect(
      find.text(
        'Past records stay; new messages from the other 4 are '
        'ignored.',
      ),
      findsOneWidget,
    );
    expect(find.text('Main line · today · 412 messages'), findsOneWidget);
    expect(find.text('Second line · 3 days ago · 96 messages'), findsOneWidget);
    expect(find.text('289 past messages'), findsOneWidget);
    expect(find.text('Not tracked'), findsNWidgets(4));
    await _tap(tester, 'lines-quick-keep');
    final lines = await tester.runAsync(() => _saved(seeded));
    expect(lines!.mainId, '1');
    expect(lines.secondId, '5');
    expect(lines.untrackedCount, 4);
    expect(find.byKey(const Key('lines-quick-setup')), findsNothing);
    expect(find.text('2 lines tracked, newest first.'), findsOneWidget);
    expect(find.text('4 lines not tracked · Manage'), findsOneWidget);
  });

  testAppWidgets("one line's sheet: the four choices", (tester) async {
    await _pump(tester, lineSheet('5'));
    expect(find.text('SIM 5'), findsOneWidget);
    expect(
      find.text(
        'Last message 3 days ago · 96 messages · balance 4,210 · '
        'since 2 Aug 2026',
      ),
      findsOneWidget,
    );
    expect(find.text('Such as Work line'), findsOneWidget);
    expect(find.text('Where its money goes'), findsOneWidget);
    expect(find.text('THIS LINE IS'), findsOneWidget);
    for (final t in [
      "Its balance is M-Pesa's first balance on Home.",
      'Its balance is added to the M-Pesa total.',
      'One SIM replaced another. Its messages join that line.',
      'Its balance leaves every total.',
    ]) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('Save'), findsOneWidget);
  });

  testAppWidgets("Don't track starts on keep; delete confirms with the count", (
    tester,
  ) async {
    final seeded = await _pump(tester, lineSheet('4'));
    await _tap(tester, 'line-is-dont');
    expect(
      find.text('New messages from it are skipped, without asking.'),
      findsOneWidget,
    );
    expect(find.text('Keep its past records'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('line-keep-records')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(find.text('Stop tracking SIM 4'), findsOneWidget);
    await _tap(tester, 'line-delete-records');
    expect(
      find.text(
        'Its 3 records leave Activity, Plan and Insights. Balances '
        'are worked out again.',
      ),
      findsOneWidget,
    );
    await _tap(tester, 'line-save');
    expect(find.text("Delete SIM 4's 3 records?"), findsOneWidget);
    expect(
      find.textContaining('the M-Pesa total drops by KES 1,020'),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final lines = await _saved(seeded);
      expect(lines.line('4')!.tracked, isFalse);
      expect(await seeded.db.select(seeded.db.transactions).get(), isEmpty);
    });
  });

  testAppWidgets('Same line as… offers tracked lines, then confirms the merge', (
    tester,
  ) async {
    final seeded = await _pump(tester, lineSheet('3'));
    await _tap(tester, 'line-is-same');
    expect(find.text('Pick the line that replaced it.'), findsOneWidget);
    expect(find.text('Since 2 Aug 2026'), findsOneWidget);
    expect(find.text('Merge'), findsOneWidget);
    await _tap(tester, 'line-same-5');
    expect(find.text('Merge into SIM 5'), findsOneWidget);
    await _tap(tester, 'line-save');
    expect(find.text('Make them one line?'), findsOneWidget);
    expect(
      find.text(
        'SIM 3 and SIM 5 become one line. 212 messages, balance continues '
        "from the newer one (SIM 5, KES 4,210). SIM 3's 860 leaves the total; "
        'its records keep their dates.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('line-merge-confirm')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final lines = await _saved(seeded);
      expect(lines.line('3'), isNull);
      expect(lines.line('5')!.messages, 212);
    });
  });

  testAppWidgets('after: tracked lines, then "N lines not tracked · Manage"', (
    tester,
  ) async {
    await _pump(tester, manyLines(), after: true);
    expect(find.text('2 lines tracked, newest first.'), findsOneWidget);
    expect(find.textContaining('Main line'), findsOneWidget);
    expect(find.textContaining('Second line'), findsOneWidget);
    expect(find.text('4 lines not tracked · Manage'), findsOneWidget);
    await _tap(tester, 'lines-manage-untracked');
    expect(find.text('NOT TRACKED (4)'), findsOneWidget);
    expect(find.byKey(const Key('line-row-4')), findsOneWidget);
  });

  testAppWidgets('the quiet note on the first skipped message shows once', (
    tester,
  ) async {
    final seeded = await _pump(
      tester,
      homeRows(),
      after: true,
      also: (s) async {
        final lines = await _saved(s);
        await DriftAppSettingsRepository(s.db).writeJson(
          mpesaLinesKey,
          lines
              .place(
                LineFacts(
                  hash: 'skip-1',
                  at: DateTime.utc(2026, 11, 21, 12),
                  sim: 'sim:4',
                  amountMinor: 1000,
                  inflow: false,
                  balanceMinor: 101000,
                ),
              )
              .$1
              .toJson(),
        );
      },
    );
    expect(
      find.text(
        'A new message from SIM 4 was skipped, as you stopped '
        'tracking it. Later ones are skipped without a note.',
      ),
      findsOneWidget,
    );
    await _tap(tester, 'line-skip-note-ok');
    expect(find.byKey(const Key('line-skip-note')), findsNothing);
    expect(
      (await tester.runAsync(() => _saved(seeded)))!.skipNote,
      SkipNote.shown,
    );
  });

  testAppWidgets('iPhone, lines told apart by balance: the same choices', (
    tester,
  ) async {
    await _pump(tester, lineSheet('5'), iphone: true);
    expect(find.text('Line 5'), findsOneWidget);
    for (final t in [
      'Main line',
      'Second line',
      'Same line as…',
      "Don't track this line",
    ]) {
      expect(find.text(t), findsOneWidget);
    }
  });

  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    group('at ${scale}x text', () {
      testAppWidgets('M-Pesa lines and its sheets fit', (tester) async {
        await _pump(tester, manyLines(), textScale: scale);
        await _tap(tester, 'lines-old');
        expect(tester.takeException(), isNull);
      });

      testAppWidgets('the quick setup fits', (tester) async {
        await _pump(tester, manyLines(), textScale: scale);
        await _tap(tester, 'lines-quick-setup');
        await tester.ensureVisible(find.byKey(const Key('lines-quick-keep')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testAppWidgets("a line's sheet fits", (tester) async {
        await _pump(tester, lineSheet('4'), textScale: scale);
        await _tap(tester, 'line-is-dont');
        await tester.ensureVisible(find.byKey(const Key('line-save')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _tap(tester, 'line-is-same');
        expect(tester.takeException(), isNull);
      });

      testAppWidgets('the screen after fits', (tester) async {
        await _pump(tester, manyLines(), after: true, textScale: scale);
        await _tap(tester, 'lines-manage-untracked');
        expect(tester.takeException(), isNull);
      });
    });
  }
}
