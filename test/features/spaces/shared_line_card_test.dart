import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/spaces/line_routing.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/spaces/application/routing_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/features/spaces/presentation/shared_line_card.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

class _Router implements SharedLineRouter {
  final answers = <(int, bool, bool)>[];

  @override
  Future<void> answer(
    SharedLineQuestion question, {
    required String businessId,
    required bool forBusiness,
    required bool always,
  }) async {
    expect(businessId, 'shop1');
    answers.add((question.transactionId, forBusiness, always));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SharedLineQuestion question(int id, {bool inflow = true, String? name}) =>
    SharedLineQuestion(
      transactionId: id,
      institutionId: 'mpesa',
      amountMinor: 65000,
      currency: 'KES',
      isInflow: inflow,
      at: DateTime.utc(2026, 11, 19),
      name: name,
      personKey: name == null ? null : personKey(name: name),
    );

void main() {
  late _Router router;
  late List<SharedLineQuestion> queue;

  setUp(() {
    router = _Router();
    queue = [
      question(1, name: 'GRACE WAMBUI'),
      question(2, inflow: false, name: 'MZEE JUMA'),
    ];
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeSpaceProvider.overrideWithValue(
            const Space(
              id: 'shop1',
              name: 'Vegetable stall',
              kind: SpaceKind.business,
            ),
          ),
          sharedLineRouterProvider.overrideWithValue(router),
          sharedLineQuestionsProvider.overrideWith((ref) async => [...queue]),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: SharedLineCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('asks about the newest payment, then the next', (tester) async {
    await pump(tester);
    expect(
      find.text('Grace Wambui sent you KES 650. Was this for the business?'),
      findsOneWidget,
    );
    expect(find.text('Always do this for Grace Wambui'), findsOneWidget);
    expect(find.text('1 more to sort'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shared-line-business')));
    queue.removeAt(0);
    await tester.pumpAndSettle();
    expect(router.answers, [(1, true, true)]);
    expect(
      find.text('You paid Mzee Juma KES 650. Was this for the business?'),
      findsOneWidget,
    );
    expect(find.text('Business cost'), findsOneWidget);

    // Untick "Always", then keep it personal.
    await tester.tap(find.byKey(const Key('shared-line-always')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('shared-line-personal')));
    queue.clear();
    await tester.pumpAndSettle();
    expect(router.answers.last, (2, false, false));
    expect(find.byKey(const Key('home-shared-line')), findsNothing);
  });

  testWidgets('without a name it does not offer "Always"', (tester) async {
    queue = [question(3)];
    await pump(tester);
    expect(
      find.text('Someone sent you KES 650. Was this for the business?'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shared-line-always')), findsNothing);
  });
}
