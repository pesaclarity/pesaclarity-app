import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/ask/answer.dart';
import 'package:pesaclarity/src/features/ask/model/model_answer.dart';
import 'package:pesaclarity/src/features/ask/model/slm_facts.dart';
import 'package:pesaclarity/src/features/ask/model/slm_generator.dart';

/// Replies with [reply], or fails, or never finishes.
class _Fake implements SlmGenerator {
  _Fake(this.reply, {this.fails = false, this.hangs = false});

  final String reply;
  final bool fails;
  final bool hangs;
  bool stopped = false;
  int asked = 0;

  @override
  Stream<SlmEvent> ask({required String system, required String question}) {
    asked++;
    if (hangs) return StreamController<SlmEvent>().stream;
    if (fails) return Stream.value(const SlmFailed('no'));
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
  void stop() => stopped = true;

  @override
  Future<void> close() async {}
}

const _facts = SlmFacts([
  SlmFactSection('Top spending this month', [
    'Rent: KES 15,000',
    'Food: KES 12,400',
  ]),
]);

final _fallback = AskAnswer(
  kind: ReplyKind.total,
  template: 'You spent {amount} on food.',
  facts: const {'amount': 1240000},
  asOf: DateTime(2026, 11, 20),
  figureMinor: 1240000,
);

const _chart = '{"chart":"none","data":"none","period":"this_month"}';

Future<AskAnswer> _answer(_Fake g, {AskAnswer? fallback}) => answerWithModel(
  generator: g,
  question: 'Where did my money go?',
  facts: _facts,
  fallback: fallback ?? _fallback,
  timeout: const Duration(milliseconds: 200),
);

void main() {
  test(
    'a grounded reply with a strict chart line becomes the answer',
    () async {
      final a = await _answer(
        _Fake('$_chart\nRent took KES 15,000 and food KES 12,400.'),
      );
      expect(a.template, 'Rent took KES 15,000 and food KES 12,400.');
      expect(a.kind, ReplyKind.total);
      expect(a.figureMinor, 1240000);
    },
  );

  test('a question only the model answers becomes a model reply', () async {
    final cant = AskAnswer(
      kind: ReplyKind.cant,
      template: 'I can only answer from your records.',
      asOf: DateTime(2026, 11, 20),
      suggestions: const ['How much did I spend?'],
    );
    final a = await _answer(
      _Fake('$_chart\nRent is your biggest cost.'),
      fallback: cant,
    );
    expect(a.kind, ReplyKind.model);
    expect(a.suggestions, isEmpty);
    expect(a.canUpdate, isFalse);
  });

  test('falls back silently on a number that is not in the facts', () async {
    final a = await _answer(_Fake('$_chart\nYou spent KES 99,999 on food.'));
    expect(identical(a, _fallback), isTrue);
  });

  test('falls back on a broken chart line', () async {
    for (final reply in [
      'Rent took KES 15,000.',
      '{"chart":"pie","data":"none","period":"this_month"}\nRent.',
      '{"chart":"bar"\nRent.',
    ]) {
      expect(identical(await _answer(_Fake(reply)), _fallback), isTrue);
    }
  });

  test('falls back when the model fails or takes too long', () async {
    expect(identical(await _answer(_Fake('', fails: true)), _fallback), isTrue);
    final slow = _Fake('', hangs: true);
    expect(identical(await _answer(slow), _fallback), isTrue);
    expect(slow.stopped, isTrue);
  });

  test('never asks the model to clarify or for small talk', () async {
    for (final kind in [ReplyKind.clarify, ReplyKind.hi, ReplyKind.help]) {
      final g = _Fake('$_chart\nHello.');
      final f = AskAnswer(kind: kind, template: 'x', asOf: DateTime(2026));
      expect(identical(await _answer(g, fallback: f), f), isTrue);
      expect(g.asked, 0);
    }
  });

  test('braces in the reply are not read as placeholders', () async {
    final a = await _answer(_Fake('$_chart\nRent {is} the most.'));
    expect(a.template, 'Rent (is) the most.');
  });
}
