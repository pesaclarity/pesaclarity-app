import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/app.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/features/home/application/cash_flow_forecast_provider.dart';
import 'package:pesaclarity/src/features/home/application/health_index_provider.dart';
import 'package:pesaclarity/src/features/home/application/safe_to_spend_provider.dart';

Future<void> _pumpApp(
  WidgetTester tester, {
  AppFlavor flavor = AppFlavor.foss,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appFlavorProvider.overrideWithValue(flavor),
        safeToSpendTodayProvider.overrideWith((ref) async => null),
        cashFlowForecastProvider.overrideWith((ref) async => null),
        healthIndexProvider.overrideWith((ref) async => null),
      ],
      child: const PesaClarityApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _finishOnboarding(WidgetTester tester) async {
  await tester.tap(find.text('Get started'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start the 90-day scan'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts in onboarding and reaches Home', (tester) async {
    await _pumpApp(tester);

    expect(
      find.text('Your money, made clear, without giving your data away.'),
      findsOneWidget,
    );
    expect(find.text('Continue with Google'), findsNothing);

    await _finishOnboarding(tester);

    expect(find.text('How am I doing today?'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('offers Google sign-in only in the play flavour', (tester) async {
    await _pumpApp(tester, flavor: AppFlavor.play);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('switches between the five tabs', (tester) async {
    await _pumpApp(tester);
    await _finishOnboarding(tester);

    const tabs = {
      'Activity': 'Where did my money go?',
      'Plan': "What's coming, and is it covered?",
      'Goals': 'Am I getting there?',
      'Insights': 'What should I change?',
      'Home': 'How am I doing today?',
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

  testWidgets('opens Debts from Goals and Profile from Home', (tester) async {
    await _pumpApp(tester);
    await _finishOnboarding(tester);

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
