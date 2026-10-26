import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';

import '../helpers/test_app.dart';

Finder _button(String label) => find.widgetWithText(FilledButton, label);

void main() {
  testAppWidgets('ticking institutions saves them and unlocks the scan', (
    tester,
  ) async {
    final db = openTestDatabase();
    final repo = DriftInstitutionsRepository(db);
    await pumpApp(tester, db: db);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('Which accounts do you use?'), findsOneWidget);
    expect(find.text('Messages from MPESA'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(_button('Scan my messages')).enabled,
      isFalse,
    );
    expect(find.text('Tick at least one account to continue.'), findsOneWidget);

    await tester.tap(find.text('M-Pesa'));
    await tester.tap(find.text('KCB'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(repo.selectedIds), {'mpesa', 'kcb'});

    await tester.tap(find.text('KCB'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(repo.selectedIds), {'mpesa'});
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'M-Pesa'),
          )
          .value,
      isTrue,
    );

    expect(
      tester.widget<FilledButton>(_button('Scan my messages')).enabled,
      isTrue,
    );
    await tester.tap(_button('Scan my messages'));
    await tester.pumpAndSettle();
    expect(find.text('How am I doing today?'), findsOneWidget);
  });

  testAppWidgets('institution rows meet the 44px target and are labelled', (
    tester,
  ) async {
    await pumpApp(tester, db: openTestDatabase());
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    const senders = {'M-Pesa': 'MPESA', 'I&M Bank': 'I&M', 'KCB': 'KCB'};
    for (final MapEntry(key: name, value: sender) in senders.entries) {
      final tile = find.widgetWithText(CheckboxListTile, name);
      expect(tester.getSize(tile).height, greaterThanOrEqualTo(44));
      expect(
        tester.getSemantics(tile),
        isSemantics(
          label: '$name\nMessages from $sender',
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testAppWidgets('Profile > My accounts switches institutions on and off', (
    tester,
  ) async {
    final db = openTestDatabase();
    final repo = DriftInstitutionsRepository(db);
    await pumpApp(tester, db: db);
    await finishOnboarding(tester);

    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My accounts'));
    await tester.pumpAndSettle();

    SwitchListTile tile(String name) =>
        tester.widget(find.widgetWithText(SwitchListTile, name));
    expect(tile('M-Pesa').value, isTrue);
    expect(tile('I&M Bank').value, isFalse);

    await tester.tap(find.text('I&M Bank'));
    await tester.pumpAndSettle();
    expect(tile('I&M Bank').value, isTrue);
    expect(await tester.runAsync(repo.selectedIds), {'mpesa', 'im_bank'});

    await tester.tap(find.text('M-Pesa'));
    await tester.tap(find.text('I&M Bank'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(repo.selectedIds), isEmpty);
    expect(
      find.text('All accounts are off, so no messages are read.'),
      findsOneWidget,
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });
}
