// On an iPhone simulator, the experiment's language model runs on rayo
// (SLM_EXPERIMENT, test builds only) and answers from made-up facts, with
// its speed printed. ios-model-test.yml passes the file it downloaded from
// the slm-models release:
//
//   flutter test integration_test/slm_experiment_test.dart -d <device> \
//     --dart-define=SLM_MODEL_PATH=/path/to/the.weights
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pesaclarity/src/features/slm_experiment/data/slm_generator.dart';
import 'package:pesaclarity/src/features/slm_experiment/domain/slm_answer.dart';
import 'package:pesaclarity/src/features/slm_experiment/domain/slm_facts.dart';

const _path = String.fromEnvironment('SLM_MODEL_PATH');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the language model answers on rayo and reports its speed',
    () async {
      const facts = SlmFacts([
        SlmFactSection('Today', ['20 Nov 2026']),
        SlmFactSection('Money in and out', [
          'This month so far (Nov 2026): money in KES 80,000, '
              'spent KES 31,600, left KES 48,400',
        ]),
        SlmFactSection('Top spending this month', [
          'Rent: KES 15,000',
          'Food: KES 12,400',
        ]),
      ]);
      final generator = RayoSlmGenerator(path: _path);
      final answer = StringBuffer();
      SlmStats? stats;
      await for (final event in generator.ask(
        system: slmSystem(facts),
        question: 'Where did my money go this month?',
      )) {
        switch (event) {
          case SlmPiece(:final text):
            answer.write(text);
          case SlmDone(stats: final s):
            stats = s;
          case SlmFailed(:final reason):
            fail(reason);
        }
      }
      await generator.close();
      debugPrint('SLM answer: $answer');
      final parsed = SlmAnswer.parse(answer.toString());
      final choice = parsed.choice;
      debugPrint(
        'SLM choice: ${choice == null ? 'not the schema' : '${choice.chart.name} ${choice.data.name} ${choice.period.name}'}',
      );
      debugPrint(
        'SLM check: ${ungroundedNumbers(parsed.text, facts.text).join(', ')}',
      );
      debugPrint('SLM stats: ${stats!.line}');
      expect(answer.toString().trim(), isNotEmpty);
      expect(stats.replyTokens, greaterThan(0));
    },
    skip: _path.isEmpty ? 'no SLM_MODEL_PATH given' : null,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
