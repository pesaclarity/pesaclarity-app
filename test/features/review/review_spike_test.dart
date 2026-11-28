import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/domain/reader/review_spike.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/backup/data/key_value_store.dart';
import 'package:pesaclarity/src/features/review/application/review_providers.dart';
import 'package:pesaclarity/src/features/review/application/review_spike_providers.dart';
import 'package:pesaclarity/src/features/review/presentation/review_spike_card.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

// Made-up institutions and times only.
final _now = DateTime.utc(2031, 3, 10, 12);

ReviewSpikeItem _item(int id, String inst, Duration ago) =>
    (id: id, institutionId: inst, receivedAt: _now.subtract(ago));

List<ReviewSpikeItem> _burst(String inst, int count, {int from = 1}) => [
  for (var i = 0; i < count; i++) _item(from + i, inst, Duration(hours: 1 + i)),
];

ReviewItem _row(ReviewSpikeItem i) => ReviewItem(
  id: i.id,
  institutionId: i.institutionId,
  sender: 'ZEDBANK',
  receivedAt: i.receivedAt,
  messageHash: 'hash-${i.id}',
  body: 'Ref QZX${i.id} invented text',
  reason: 'no rule',
);

void main() {
  group('reviewSpikes', () {
    test('a burst from one institution is a spike', () {
      final spikes = reviewSpikes(_burst('zedbank', 7), now: _now);
      expect(spikes, [
        const ReviewSpike(institutionId: 'zedbank', waiting: 7, newestId: 7),
      ]);
    });

    test('too few new messages is not a spike', () {
      expect(reviewSpikes(_burst('zedbank', 4), now: _now), isEmpty);
    });

    test('messages spread over days are not a spike', () {
      final items = [
        for (var d = 0; d < 10; d++) _item(d + 1, 'zedbank', Duration(days: d)),
      ];
      expect(reviewSpikes(items, now: _now), isEmpty);
    });

    test('a burst no bigger than the usual is not a spike', () {
      // 28 in the two weeks before: 2 a day, so 5 today is under 3x.
      final usual = [
        for (var i = 0; i < 28; i++)
          _item(100 + i, 'zedbank', Duration(hours: 30 + i * 11)),
      ];
      expect(
        reviewSpikes([...usual, ..._burst('zedbank', 5)], now: _now),
        isEmpty,
      );
      expect(
        reviewSpikes([...usual, ..._burst('zedbank', 6)], now: _now),
        hasLength(1),
      );
    });

    test('only the institution that jumped', () {
      final spikes = reviewSpikes([
        ..._burst('zedbank', 6),
        _item(50, 'otherpay', const Duration(hours: 2)),
      ], now: _now);
      expect(spikes.single.institutionId, 'zedbank');
    });

    test('a spike already told about is not told again', () {
      final items = _burst('zedbank', 6);
      expect(reviewSpikes(items, now: _now, toldUpTo: {'zedbank': 6}), isEmpty);
      // A new burst after it is a new spike.
      expect(
        reviewSpikes(
          [...items, ..._burst('zedbank', 5, from: 20)],
          now: _now,
          toldUpTo: {'zedbank': 6},
        ).single.newestId,
        24,
      );
    });
  });

  group('ReviewSpikeCard', () {
    Future<KeyValueStore> pump(
      WidgetTester tester,
      List<ReviewSpikeItem> items, {
      KeyValueStore? store,
    }) async {
      final kv = store ?? MemoryKeyValueStore();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: SingleChildScrollView(child: ReviewSpikeCard()),
            ),
          ),
          GoRoute(
            path: AppRoutes.review,
            builder: (_, _) => const Scaffold(body: Text('inbox')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => _now),
            reviewSpikeStoreProvider.overrideWithValue(kv),
            institutionCatalogueProvider.overrideWithValue(const []),
            pendingReviewProvider.overrideWith(
              (ref) => Stream.value([for (final i in items) _row(i)]),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return kv;
    }

    testWidgets('shows a spike, and once closed not again', (tester) async {
      final items = _burst('zedbank', 6);
      final store = await pump(tester, items);
      expect(find.text('zedbank messages changed format'), findsOneWidget);
      expect(
        find.text('6 need checking. Check one and the rest follow.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-spike-zedbank')), findsNothing);

      // After a restart, the same spike stays told.
      await tester.pumpWidget(const SizedBox());
      await pump(tester, items, store: store);
      expect(find.byKey(const Key('review-spike-zedbank')), findsNothing);
    });

    testWidgets('no card without a spike', (tester) async {
      await pump(tester, _burst('zedbank', 3));
      expect(find.byKey(const Key('review-spike-zedbank')), findsNothing);
    });

    testWidgets('tapping opens messages to check', (tester) async {
      await pump(tester, _burst('zedbank', 6));
      await tester.tap(find.text('zedbank messages changed format'));
      await tester.pumpAndSettle();
      expect(find.text('inbox'), findsOneWidget);
    });
  });
}
