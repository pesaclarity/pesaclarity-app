import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/features/slm_experiment/data/slm_facts_loader.dart';
import 'package:pesaclarity/src/features/slm_experiment/data/slm_generator.dart';
import 'package:pesaclarity/src/features/slm_experiment/domain/slm_facts.dart';
import 'package:pesaclarity/src/features/slm_experiment/presentation/slm_experiment_screen.dart';

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

Future<_FakeGenerator> _pump(WidgetTester tester) async {
  final fake = _FakeGenerator();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        slmGeneratorProvider.overrideWithValue(fake),
        slmFactsProvider.overrideWith((ref) async => _facts),
      ],
      child: const MaterialApp(home: SlmExperimentScreen()),
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

  testWidgets('records that cannot be read: a plain message and Retry', (
    tester,
  ) async {
    final fake = _FakeGenerator();
    var reads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          slmGeneratorProvider.overrideWithValue(fake),
          slmFactsProvider.overrideWith((ref) async {
            reads++;
            if (reads == 1) throw StateError('Cannot use the Ref of thing');
            return _facts;
          }),
        ],
        child: const MaterialApp(home: SlmExperimentScreen()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byKey(const Key('slm-input')), 'hello');
    await tester.tap(find.byKey(const Key('slm-ask')));
    await tester.pump();
    expect(find.text("Couldn't read your records. Try again."), findsOneWidget);
    expect(find.textContaining('Cannot use the Ref'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);
    expect(fake.question, isNull);

    await tester.tap(find.byKey(const Key('slm-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('slm-retry')), findsNothing);
    expect(fake.question, 'hello');
    expect(fake.system, contains('Rent: KES 15,000'));
  });
}
