import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/repositories/purpose_repository.dart';
import 'package:pesaclarity/src/domain/income/money_purpose.dart';
import 'package:pesaclarity/src/features/income/presentation/what_was_this_sheet.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

class _FakePurpose implements PurposeRepository {
  final answers = <(int, MoneyPurpose, bool)>[];

  @override
  Future<void> answer(
    int transactionId,
    MoneyPurpose purpose, {
    bool alwaysUse = false,
  }) async => answers.add((transactionId, purpose, alwaysUse));

  @override
  Future<void> noteChoice(int transactionId, int categoryId) async {}

  @override
  Future<void> setAskPurpose(int payeeId, {required bool ask}) async {}
}

void main() {
  testWidgets('asks what it was, then saves the answer', (tester) async {
    final fake = _FakePurpose();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [purposeRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: WhatWasThisSheet(
              transactionId: 4,
              payeeName: 'Test Wanjiku',
              amountMinor: 300000,
              currency: 'KES',
            ),
          ),
        ),
      ),
    );

    expect(find.text('What was this?'), findsOneWidget);
    expect(find.textContaining('from Test Wanjiku'), findsOneWidget);
    expect(find.text('Added to Debts'), findsOneWidget);
    final save = find.byKey(const Key('purpose-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.tap(find.byKey(const Key('purpose-gift')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('purpose-always')));
    await tester.tap(find.byKey(const Key('purpose-always')));
    await tester.pump();
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(fake.answers, [(4, MoneyPurpose.gift, true)]);
  });
}
