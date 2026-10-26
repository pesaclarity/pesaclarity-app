import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/flavor.dart';

import '../helpers/test_app.dart';

void main() {
  testAppWidgets('starts in onboarding and reaches Home', (tester) async {
    await pumpApp(tester, db: openTestDatabase());

    expect(
      find.text('Your money, made clear, without giving your data away.'),
      findsOneWidget,
    );
    expect(find.text('Continue with Google'), findsNothing);

    await finishOnboarding(tester);

    expect(find.text('Safe to spend today'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    // With no accounts or transactions yet, Home has no index or forecast.
    expect(find.text('Financial Health Index'), findsNothing);
    expect(find.textContaining('At this pace'), findsNothing);
  });

  testAppWidgets('offers Google sign-in only in the play flavour', (
    tester,
  ) async {
    await pumpApp(tester, db: openTestDatabase(), flavor: AppFlavor.play);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testAppWidgets('switches between the five tabs', (tester) async {
    await pumpApp(tester, db: openTestDatabase());
    await finishOnboarding(tester);

    const tabs = {
      'Activity': 'Search payee, amount, note',
      'Plan': 'Planned of expected income',
      'Goals': 'Am I getting there?',
      'Insights': 'What should I change?',
      'Home': 'Safe to spend today',
    };
    for (final MapEntry(key: label, value: question) in tabs.entries) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(question), findsOneWidget, reason: label);
    }
  });

  testAppWidgets('opens Debts from Goals and Profile from Home', (
    tester,
  ) async {
    await pumpApp(tester, db: openTestDatabase());
    await finishOnboarding(tester);

    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Your account and settings'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Goals'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('See debts'));
    await tester.pumpAndSettle();
    expect(find.text('When will I be debt-free?'), findsOneWidget);
  });
}
