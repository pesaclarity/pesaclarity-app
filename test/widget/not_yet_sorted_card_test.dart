import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pesaclarity/src/domain/ledger/not_yet_sorted.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/home/application/not_yet_sorted_provider.dart';
import 'package:pesaclarity/src/features/home/presentation/not_yet_sorted_card.dart';
import 'package:pesaclarity/src/features/security/application/balance_visibility.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';
import 'package:pesaclarity/src/shared/widgets/amounts_hidden.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/app_fonts.dart';

final _card = find.byKey(const Key('home-review'));

/// Pumps the card over [sorted], with stand-ins for the screens it opens.
/// Returns where the app went, once tapped.
Future<GoRouter> _pump(
  WidgetTester tester,
  NotYetSorted sorted, {
  bool hidden = false,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: AmountsHidden(
            hidden: hidden,
            child: const SingleChildScrollView(child: NotYetSortedCard()),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.review,
        builder: (_, _) => const Text('review screen'),
      ),
      GoRoute(
        path: AppRoutes.activity,
        builder: (_, _) => const Text('activity screen'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [notYetSortedProvider.overrideWith((ref) async => sorted)],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  setUpAll(loadAppFonts);

  testWidgets('hidden when nothing is unsorted', (tester) async {
    await _pump(tester, const NotYetSorted());
    expect(_card, findsNothing);
  });

  testWidgets('messages with a known amount', (tester) async {
    await _pump(
      tester,
      const NotYetSorted(amountMinor: 1240000, messagesToCheck: 3),
    );
    expect(find.text('KES 12,400 not yet sorted'), findsOneWidget);
    expect(find.text('3 messages to check'), findsOneWidget);
    await tester.tap(_card);
    await tester.pumpAndSettle();
    expect(find.text('review screen'), findsOneWidget);
  });

  testWidgets('messages the reader could not read keep today\'s title', (
    tester,
  ) async {
    await _pump(tester, const NotYetSorted(messagesToCheck: 1));
    expect(find.text('1 message to check'), findsOneWidget);
    expect(find.textContaining('not yet sorted'), findsNothing);
    final tile = tester.widget<ListTile>(_card);
    expect(tile.subtitle, isNull);
  });

  testWidgets('people not named only opens their money in Activity', (
    tester,
  ) async {
    final router = await _pump(
      tester,
      NotYetSorted(
        amountMinor: 450000,
        peopleNotNamed: 1,
        firstNotNamed: CalendarDate(2026, 11, 8),
      ),
    );
    expect(find.text('KES 4,500 not yet sorted'), findsOneWidget);
    expect(find.text('1 person not named'), findsOneWidget);
    await tester.tap(_card);
    await tester.pumpAndSettle();
    expect(_location(router), '/activity?type=moneyIn&from=2026-11-08');
  });

  testWidgets('both, messages first, and the tap checks messages', (
    tester,
  ) async {
    await _pump(
      tester,
      const NotYetSorted(
        amountMinor: 1240000,
        messagesToCheck: 3,
        peopleNotNamed: 2,
      ),
    );
    expect(find.text('KES 12,400 not yet sorted'), findsOneWidget);
    expect(
      find.text('3 messages to check · 2 people not named'),
      findsOneWidget,
    );
    await tester.tap(_card);
    await tester.pumpAndSettle();
    expect(find.text('review screen'), findsOneWidget);
  });

  testWidgets('hides the amount with the eye', (tester) async {
    await _pump(
      tester,
      const NotYetSorted(amountMinor: 1240000, peopleNotNamed: 2),
      hidden: true,
    );
    expect(find.textContaining('12,400'), findsNothing);
    expect(find.text('KES $maskedDigits not yet sorted'), findsOneWidget);
    expect(find.text('2 people not named'), findsOneWidget);
  });

  testWidgets('a large amount stays whole at twice the text on 320dp', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(
      tester,
      const NotYetSorted(
        amountMinor: 123456700,
        messagesToCheck: 12,
        peopleNotNamed: 14,
      ),
    );
    expect(tester.takeException(), isNull);
    const title = 'KES 1,234,567 not yet sorted';
    final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
    final number = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 4, extentOffset: 13),
    );
    expect(number.map((b) => b.top).toSet(), hasLength(1));
    expect(
      number.map((b) => b.right).reduce((a, b) => a > b ? a : b),
      lessThanOrEqualTo(paragraph.size.width + 0.5),
    );
  });
}
