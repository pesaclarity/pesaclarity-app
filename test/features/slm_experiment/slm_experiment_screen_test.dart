import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/slm_experiment/data/slm_facts_loader.dart';
import 'package:pesaclarity/src/features/slm_experiment/data/slm_generator.dart';
import 'package:pesaclarity/src/features/slm_experiment/domain/slm_facts.dart';
import 'package:pesaclarity/src/features/slm_experiment/presentation/slm_experiment_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

/// Hands out a reply a piece at a time, as the test says.
class _FakeGenerator implements SlmGenerator {
  StreamController<SlmEvent>? reply;
  String? system;
  String? question;
  bool stopped = false;

  @override
  Stream<SlmEvent> ask({required String system, required String question}) {
    this.system = system;
    this.question = question;
    return (reply = StreamController<SlmEvent>()).stream;
  }

  @override
  void stop() {
    stopped = true;
    reply!
      ..add(
        const SlmDone(
          SlmStats(
            promptTokens: 400,
            replyTokens: 2,
            seconds: 0.5,
            rssBytes: 300 * 1024 * 1024,
            threads: 4,
          ),
        ),
      )
      ..close();
  }

  @override
  Future<void> close() async {}
}

const _facts = SlmFacts([
  SlmFactSection('Top spending this month', ['Rent: KES 15,000']),
]);

Future<_FakeGenerator> _pump(
  WidgetTester tester, {
  SlmFacts facts = _facts,
}) async {
  final fake = _FakeGenerator();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        slmGeneratorProvider.overrideWithValue(fake),
        slmFactsProvider.overrideWith((ref) async => facts),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const SlmExperimentScreen(),
      ),
    ),
  );
  return fake;
}

void main() {
  testWidgets('a preset streams an answer and shows what the model saw', (
    tester,
  ) async {
    final fake = await _pump(tester);
    expect(find.textContaining('Nothing you type'), findsOneWidget);

    await tester.tap(find.byKey(const Key('slm-preset-0')));
    await tester.pump();
    expect(fake.question, 'Where did my money go this month?');
    expect(fake.system, contains('Rent: KES 15,000'));
    expect(find.byKey(const Key('slm-stop')), findsOneWidget);

    fake.reply!.add(const SlmPiece('Most went '));
    await tester.pump();
    fake.reply!.add(const SlmPiece('on Rent.'));
    await tester.pump();
    expect(find.text('Most went on Rent.'), findsOneWidget);

    fake.reply!.add(
      const SlmDone(
        SlmStats(
          promptTokens: 412,
          replyTokens: 20,
          seconds: 2,
          rssBytes: 286 * 1024 * 1024,
          threads: 4,
          loadSeconds: 1.5,
        ),
      ),
    );
    await fake.reply!.close();
    await tester.pump();
    expect(find.textContaining('10.0 tokens/s'), findsOneWidget);
    expect(find.textContaining('286 MB'), findsOneWidget);
    expect(find.byKey(const Key('slm-ask')), findsOneWidget);

    await tester.tap(find.textContaining('What the model saw (1 facts)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('- Rent: KES 15,000'), findsOneWidget);

    await tester.tap(find.byKey(const Key('slm-clear')));
    await tester.pump();
    expect(find.text('Most went on Rent.'), findsNothing);
  });

  testWidgets(
    'a chart answer draws the app\'s numbers and flags a made-up one',
    (tester) async {
      final today = CalendarDate(2026, 11, 20);
      LedgerEntry out(int id, int minor, int category) => LedgerEntry(
        id: id,
        accountId: 1,
        occurredAt: today.startInstant.add(const Duration(hours: 9)),
        amountMinor: minor,
        direction: TransactionDirection.outflow,
        kind: TransactionKind.till,
        categoryId: category,
        categoryType: CategoryType.expense,
      );
      final facts = SlmFacts.of(
        SlmFactsInput(
          today: today,
          entries: [out(1, 1500000, 1), out(2, 1240000, 2)],
          categoryNames: const {1: 'Rent', 2: 'Food'},
        ),
      );
      final fake = await _pump(tester, facts: facts);
      await tester.tap(find.byKey(const Key('slm-preset-0')));
      await tester.pump();
      fake.reply!.add(
        const SlmPiece(
          '{"chart":"bar","data":"top_categories","period":"this_month"}\n',
        ),
      );
      await tester.pump();
      // The chart line is never shown as words.
      expect(find.textContaining('"chart"'), findsNothing);
      fake.reply!.add(
        const SlmPiece(
          'Rent is your biggest spend at KES 15,000. Food is KES 12,500.',
        ),
      );
      fake.reply!.add(
        const SlmDone(
          SlmStats(
            promptTokens: 400,
            replyTokens: 40,
            seconds: 2,
            rssBytes: 200 * 1024 * 1024,
            threads: 4,
          ),
        ),
      );
      await fake.reply!.close();
      await tester.pump();
      expect(find.byKey(const Key('slm-chart')), findsOneWidget);
      expect(find.byKey(const Key('slm-chart-bars')), findsOneWidget);
      expect(find.text('Spending by category, this month'), findsOneWidget);
      // The bars carry the app's amounts.
      expect(find.textContaining('12,400'), findsOneWidget);
      expect(find.textContaining('15,000'), findsWidgets);
      // 12,500 is not in the facts.
      expect(find.byKey(const Key('slm-check-12,500')), findsOneWidget);
      expect(find.byKey(const Key('slm-check-15,000')), findsNothing);
    },
  );

  testWidgets('a donut answer draws the ring; a broken line shows text only', (
    tester,
  ) async {
    final today = CalendarDate(2026, 11, 20);
    final facts = SlmFacts.of(
      SlmFactsInput(
        today: today,
        entries: [
          LedgerEntry(
            id: 1,
            accountId: 1,
            occurredAt: today.startInstant.add(const Duration(hours: 9)),
            amountMinor: 500000,
            direction: TransactionDirection.outflow,
            kind: TransactionKind.till,
            categoryId: 1,
            categoryType: CategoryType.expense,
          ),
        ],
        categoryNames: const {1: 'Rent'},
      ),
    );
    final fake = await _pump(tester, facts: facts);
    await tester.tap(find.byKey(const Key('slm-preset-0')));
    await tester.pump();
    fake.reply!
      ..add(
        const SlmPiece(
          '{"chart":"donut","data":"top_categories","period":"this_month"}\n'
          'All of it went to Rent, KES 5,000.',
        ),
      )
      ..add(
        const SlmDone(
          SlmStats(
            promptTokens: 1,
            replyTokens: 1,
            seconds: 1,
            rssBytes: 1,
            threads: 1,
          ),
        ),
      );
    await fake.reply!.close();
    await tester.pump();
    expect(find.byKey(const Key('slm-chart-ring')), findsOneWidget);

    await tester.tap(find.byKey(const Key('slm-clear')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('slm-preset-1')));
    await tester.pump();
    fake.reply!
      ..add(const SlmPiece('{"chart":"pie"}\nSpend less on Rent.'))
      ..add(
        const SlmDone(
          SlmStats(
            promptTokens: 1,
            replyTokens: 1,
            seconds: 1,
            rssBytes: 1,
            threads: 1,
          ),
        ),
      );
    await fake.reply!.close();
    await tester.pump();
    expect(find.byKey(const Key('slm-chart')), findsNothing);
    expect(find.text('Spend less on Rent.'), findsOneWidget);
  });

  testWidgets('Stop ends the reply; a typed question is asked', (tester) async {
    final fake = await _pump(tester);
    await tester.enterText(find.byKey(const Key('slm-input')), 'Fees?');
    await tester.tap(find.byKey(const Key('slm-ask')));
    await tester.pump();
    expect(fake.question, 'Fees?');
    await tester.tap(find.byKey(const Key('slm-stop')));
    await tester.pump();
    expect(fake.stopped, isTrue);
    expect(find.byKey(const Key('slm-ask')), findsOneWidget);
  });

  testWidgets('a failure says why, with no stand-in answer', (tester) async {
    final fake = await _pump(tester);
    await tester.tap(find.byKey(const Key('slm-preset-1')));
    await tester.pump();
    fake.reply!.add(const SlmFailed("rayo's library cannot load here"));
    await fake.reply!.close();
    await tester.pump();
    expect(find.text("rayo's library cannot load here"), findsOneWidget);
    expect(find.byKey(const Key('slm-answer')), findsNothing);
  });

  test(
    'the generator fails plainly when the model is not in the build',
    () async {
      final g = RayoSlmGenerator(path: '/nowhere/$slmModelFile');
      final events = await g.ask(system: 's', question: 'q').toList();
      expect(events.single, isA<SlmFailed>());
      expect(
        (events.single as SlmFailed).reason,
        contains('not in this build'),
      );
      await g.close();
    },
  );
}
