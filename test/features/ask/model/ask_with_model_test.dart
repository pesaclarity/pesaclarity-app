import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/ask/answer.dart';
import 'package:pesaclarity/src/features/ask/application/ask_providers.dart';
import 'package:pesaclarity/src/features/ask/model/ask_model_controller.dart';
import 'package:pesaclarity/src/features/ask/model/slm_facts.dart';
import 'package:pesaclarity/src/features/ask/model/slm_facts_loader.dart';
import 'package:pesaclarity/src/features/ask/model/slm_generator.dart';

import '../../../domain/fixtures.dart';
import '../../../helpers/test_app.dart';
import '../ask_data_test.dart' show seedAsk;

class _Model implements SlmGenerator {
  _Model(this.reply);

  final String reply;
  int asked = 0;

  @override
  Stream<SlmEvent> ask({required String system, required String question}) {
    asked++;
    return Stream.fromIterable([
      SlmPiece(reply),
      const SlmDone(
        SlmStats(
          promptTokens: 1,
          replyTokens: 1,
          seconds: 1,
          rssBytes: 1,
          threads: 1,
        ),
      ),
    ]);
  }

  @override
  void stop() {}

  @override
  Future<void> close() async {}
}

const _facts = SlmFacts([
  SlmFactSection('Top spending this month', ['Food: KES 12,400']),
]);
const _chart = '{"chart":"none","data":"none","period":"this_month"}';

Future<AskAnswer> _ask(SlmGenerator? model) async {
  final db = openTestDatabase();
  addTearDown(db.close);
  await seedAsk(db);
  final c = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => eat(2026, 11, 13, 10)),
      askReaderRuntimeOpenerProvider.overrideWithValue(null),
      askWriterRuntimeOpenerProvider.overrideWithValue(null),
      askModelGeneratorProvider.overrideWithValue(model),
      slmFactsProvider.overrideWith((ref) async => _facts),
    ],
  );
  addTearDown(c.dispose);
  await c
      .read(askControllerProvider.notifier)
      .ask('How much did I spend on food this month?');
  return c.read(askControllerProvider).messages.last.answer!;
}

void main() {
  test('with No model, Ask answers exactly as before', () async {
    final rules = await _ask(null);
    expect(rules.kind, isNot(ReplyKind.model));
    final ungrounded = _Model('$_chart\nYou spent KES 1 on food.');
    final fallback = await _ask(ungrounded);
    expect(ungrounded.asked, 1);
    expect(fallback.toJson()..remove('asOf'), rules.toJson()..remove('asOf'));
  });

  test('with a model, its grounded words are the answer', () async {
    final a = await _ask(_Model('$_chart\nFood took KES 12,400 this month.'));
    expect(a.template, 'Food took KES 12,400 this month.');
  });
}
