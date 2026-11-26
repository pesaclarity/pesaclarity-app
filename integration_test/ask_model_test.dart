// On an iPhone simulator, Ask's money model runs on rayo and answers from
// made-up facts, with its speed printed. ios-model-test.yml passes the file it downloaded from
// the slm-models release:
//
//   flutter test integration_test/ask_model_test.dart -d <device> \
//     --dart-define=SLM_MODEL_PATH=/path/to/smollm2-360m-instruct-q4.weights
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pesaclarity/src/features/ask/model/slm_facts.dart';
import 'package:pesaclarity/src/features/ask/model/slm_generator.dart';

const _path = String.fromEnvironment('SLM_MODEL_PATH');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the language model answers on rayo and reports its speed',
    () async {
      const facts = SlmFacts([
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
      debugPrint('SLM stats: ${stats!.line}');
      expect(answer.toString().trim(), isNotEmpty);
      expect(stats.replyTokens, greaterThan(0));
    },
    skip: _path.isEmpty ? 'no SLM_MODEL_PATH given' : null,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
