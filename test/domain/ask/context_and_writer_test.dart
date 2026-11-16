import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/ask/answer.dart';
import 'package:pesaclarity/src/domain/ask/context.dart';
import 'package:pesaclarity/src/domain/ask/matcher.dart';
import 'package:pesaclarity/src/domain/ask/model_question_reader.dart';
import 'package:pesaclarity/src/domain/ask/periods.dart';
import 'package:pesaclarity/src/domain/ask/reply_writer.dart';
import 'package:pesaclarity/src/domain/ask/rule_question_reader.dart';
import 'package:pesaclarity/src/domain/ask/understanding.dart';
import 'package:pesaclarity/src/domain/reader/reader_tokens.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/ask/data/ask_model_store.dart';

void main() {
  final today = CalendarDate(2026, 11, 13);
  final now = DateTime.utc(2026, 11, 13, 9);
  const food = AskEntity(SlotKind.category, 'c:1', 'Food');
  const naivas = AskEntity(SlotKind.payee, 'p:3', 'Naivas');
  final october = AskPeriod.month(YearMonth(2026, 10), today);

  group('AskContext', () {
    final start = AskContext.empty.merge(
      intent: AskIntent.spent,
      named: {SlotKind.category: food},
      period: october,
      now: now,
    );

    test('a refining question changes only what it names', () {
      final next = start.merge(
        intent: AskIntent.refine,
        named: {SlotKind.payee: naivas},
        period: null,
        now: now,
      );
      expect(next.intent, AskIntent.spent);
      expect(next.entities.values, containsAll([food, naivas]));
      expect(next.period, october);
    });

    test('a new view of the same thing keeps it', () {
      final next = start.merge(
        intent: AskIntent.compare,
        named: const {},
        period: null,
        now: now,
      );
      expect(next.intent, AskIntent.compare);
      expect(next.entities[SlotKind.category], food);
    });

    test('a new topic starts afresh', () {
      final next = start.merge(
        intent: AskIntent.debts,
        named: const {},
        period: null,
        now: now,
      );
      expect(next.entities, isEmpty);
      expect(next.period, isNull);
      final other = start.merge(
        intent: AskIntent.received,
        named: {SlotKind.payee: naivas},
        period: null,
        now: now,
      );
      expect(other.entities.keys, [SlotKind.payee]);
    });

    test('after 30 minutes away a refine starts afresh', () {
      final later = now.add(AskContext.idle);
      expect(start.expired(later), isTrue);
      final next = start.merge(
        intent: AskIntent.refine,
        named: {SlotKind.payee: naivas},
        period: null,
        now: later,
      );
      expect(next.entities.keys, [SlotKind.payee]);
    });

    test('a tag can be dropped', () {
      final next = start.without(SlotKind.period, now);
      expect(next.period, isNull);
      expect(next.entities[SlotKind.category], food);
      expect(start.without(SlotKind.category, now).entities, isEmpty);
    });

    test('JSON round trip', () {
      final back = AskContext.fromJson(start.toJson());
      expect(back.intent, start.intent);
      expect(back.entities[SlotKind.category], food);
      expect(back.period, october);
    });
  });

  group('reply writer', () {
    test('every template passes its own check', () {
      for (final MapEntry(key: kind, value: list)
          in TemplateReplyWriter.templates.entries) {
        for (final t in list) {
          expect(
            checkTemplate(t, placeholdersIn(t)),
            isTrue,
            reason: '${kind.name}: $t',
          );
        }
      }
    });

    test('the check refuses unknown placeholders and digits', () {
      expect(checkTemplate('Spent {amount}.', {'amount'}), isTrue);
      expect(checkTemplate('Spent {amount}.', {'count'}), isFalse);
      expect(checkTemplate('Spent {cash}.', {'cash'}), isFalse);
      expect(checkTemplate('Spent 500 on {category}.', {'category'}), isFalse);
      expect(checkTemplate('Spent {amount.', {'amount'}), isFalse);
      expect(checkTemplate('', const {}), isFalse);
    });

    test('picks only sentences whose placeholders it has', () {
      const writer = TemplateReplyWriter();
      for (var seed = 0; seed < 6; seed++) {
        final t = writer.write(ReplyKind.totalDown, {
          'count',
          'change',
          'prev_period',
        }, seed: seed);
        expect(placeholdersIn(t), {'count', 'change', 'prev_period'});
      }
      // Several sentences, so replies vary.
      final seen = {
        for (var seed = 0; seed < 10; seed++)
          writer.write(ReplyKind.total, {'count'}, seed: seed),
      };
      expect(seen.length, greaterThan(1));
    });

    test('fills money and text', () {
      final text = fillTemplate(
        'Across {count}. That is {change} less than {prev_period}.',
        {'count': '23 payments', 'change': 115000, 'prev_period': 'September'},
        money: (m) => '${m ~/ 100}',
      );
      expect(text, 'Across 23 payments. That is 1150 less than September.');
    });

    test('a model sentence that fails the check falls back', () {
      final writer = CheckedReplyWriter(_FixedWriter('You spent 5000!'));
      final t = writer.write(ReplyKind.total, {'count'});
      expect(TemplateReplyWriter.templates[ReplyKind.total], contains(t));
      final good = CheckedReplyWriter(_FixedWriter('In all, {count}.'));
      expect(good.write(ReplyKind.total, {'count'}), 'In all, {count}.');
    });
  });

  group('model question reader', () {
    final manifest = AskReaderManifest(
      modelFile: 'ask-reader.tflite',
      modelSha256: '',
      modelSizeBytes: 0,
      schemaVersion: readerSchemaVersion,
      maxTokens: readerMaxTokens,
      hashBuckets: readerHashBuckets,
      slotLabels: const ['other', 'B-category', 'I-category', 'B-period'],
      intentLabels: [for (final i in AskIntent.values) i.label],
    );

    test('joins slot labels into spans and reads the intent', () {
      // "spend on food" → other other B-category.
      final runtime = _FakeRuntime(
        slots: [
          [1, 0, 0, 0],
          [1, 0, 0, 0],
          [0, 1, 0, 0],
        ],
        intent: AskIntent.spent,
      );
      final reader = ModelQuestionReader(
        runtime,
        manifest,
        fallback: RuleQuestionReader(today: () => today),
      );
      final u = reader.read('spend on food');
      expect(u.intent, AskIntent.spent);
      expect(u.spans, [const AskSpan(SlotKind.category, 'food')]);
      expect(runtime.input, hasLength(2 * readerMaxTokens));
    });

    test('unsure or failing models fall back to the rules', () {
      final reader = ModelQuestionReader(
        _FakeRuntime(slots: const [], intent: null),
        manifest,
        fallback: RuleQuestionReader(today: () => today),
      );
      expect(reader.read('Who owes me?').intent, AskIntent.whoOwesMe);
    });

    test('an unknown label makes the model unusable', () {
      const odd = AskReaderManifest(
        modelFile: 'x',
        modelSha256: '',
        modelSizeBytes: 0,
        schemaVersion: readerSchemaVersion,
        maxTokens: readerMaxTokens,
        hashBuckets: readerHashBuckets,
        slotLabels: ['other', 'B-colour'],
        intentLabels: ['spent'],
      );
      expect(odd.incompatibilities(), isNotEmpty);
      expect(manifest.incompatibilities(), isEmpty);
    });

    test('with no files or no runtime, the rules are used', () async {
      final rules = RuleQuestionReader(today: () => today);
      expect(
        await loadAskReader(
          readAsset: (_) async => null,
          openRuntime: (_) => throw StateError('unused'),
          fallback: rules,
        ),
        same(rules),
      );
      expect(
        await loadAskReader(
          readAsset: (_) async => Uint8List(0),
          openRuntime: null,
          fallback: rules,
        ),
        same(rules),
      );
    });
  });
}

class _FixedWriter implements ReplyWriter {
  _FixedWriter(this.text);
  final String text;

  @override
  String write(ReplyKind kind, Set<String> facts, {int seed = 0}) => text;

  @override
  void close() {}
}

class _FakeRuntime implements AskReaderRuntime {
  _FakeRuntime({required this.slots, required this.intent});

  final List<List<double>> slots;
  final AskIntent? intent;
  List<int>? input;

  @override
  (List<List<double>>, List<double>) run(List<int> input) {
    this.input = input;
    if (intent == null) throw StateError('model failed');
    return (slots, [for (final i in AskIntent.values) i == intent ? 0.9 : 0.0]);
  }

  @override
  void close() {}
}
