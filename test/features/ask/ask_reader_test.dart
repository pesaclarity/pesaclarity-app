import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/ask/model_question_reader.dart';
import 'package:pesaclarity/src/domain/ask/rule_question_reader.dart';
import 'package:pesaclarity/src/domain/ask/understanding.dart';
import 'package:pesaclarity/src/domain/reader/reader_tokens.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/ask/data/ask_model_store.dart';

/// The bundled ask reader on the phrasings the first one got wrong (#238,
/// #240): counts and sums for one payee, "how much to X", money in, "X sent
/// me", account balances and names the app has never seen. The host has no
/// TFLite, so the model's outputs for these very inputs were recorded on a
/// computer with the bundled file (tool/ask_reader_decodes.py) and are
/// replayed here, first with the model alone and then with the rules behind
/// it, as the app runs it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Uint8List?> asset(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object {
      return null;
    }
  }

  final recorded = jsonDecode(
    File('test/fixtures/ask/ask_reader_decodes.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final replay = _Replay(recorded);
  tearDownAll(replay.saveMissing);

  test('the recordings are of the bundled reader', () async {
    final manifest = (jsonDecode(
      utf8.decode((await asset('$askModelFolder/$askReaderManifestFile'))!),
    ) as Map).cast<String, Object?>();
    expect(recorded['model_sha256'], manifest['model_sha256']);
  });

  Future<QuestionReader> reader(QuestionReader fallback) => loadAskReader(
    readAsset: asset,
    openRuntime: (_) => replay,
    fallback: fallback,
  );

  for (final rules in [false, true]) {
    group(rules ? 'with the rules behind it' : 'the model alone', () {
      for (final (question, intent, kind, name) in _cases) {
        test(question, () async {
          final r = await reader(
            rules
                ? RuleQuestionReader(today: () => CalendarDate(2026, 11, 16))
                : const _Unsure(),
          );
          expect(r, isA<ModelQuestionReader>());
          replay.current = question;
          final u = r.read(question);
          expect(
            replay.has(question),
            isTrue,
            reason: 'no recording: run tool/ask_reader_decodes.py',
          );
          expect(u.intent, intent, reason: 'intent');
          if (kind != null && _modelMisses.containsKey(question)) {
            if (rules) {
              // The rules find the name, and their reading stands.
              expect(
                u.spans.map((s) => s.text.toLowerCase()),
                contains(name!.toLowerCase()),
              );
            } else {
              expect(u.span(kind), isNull, reason: 'a known miss');
              final instead = _modelMisses[question];
              if (instead != null) expect(u.span(instead)?.text, name);
            }
          } else if (kind != null) {
            // The rules give names in lower case.
            expect(
              u.span(kind)?.text.toLowerCase(),
              name!.toLowerCase(),
              reason: '$kind',
            );
          } else {
            expect(
              u.spans.where(
                (s) => s.kind == SlotKind.payee || s.kind == SlotKind.account,
              ),
              isEmpty,
              reason: 'no name',
            );
          }
        });
      }
    });
  }
}

/// (question, intent, the name's slot, the name as tagged). Every name here
/// is one the model was never trained on.
const _cases = <(String, AskIntent, SlotKind?, String?)>[
  (
    'How many times did I pay Example Grocers this month?',
    AskIntent.countPayments,
    SlotKind.payee,
    'Example Grocers',
  ),
  (
    'how often do I pay Example Grocers',
    AskIntent.countPayments,
    SlotKind.payee,
    'Example Grocers',
  ),
  (
    'number of payments to Example Grocers',
    AskIntent.countPayments,
    SlotKind.payee,
    'Example Grocers',
  ),
  (
    'times I paid Example Grocers this month',
    AskIntent.countPayments,
    SlotKind.payee,
    'Example Grocers',
  ),
  (
    'How many times did I pay Zebra Hardware this month?',
    AskIntent.countPayments,
    SlotKind.payee,
    'Zebra Hardware',
  ),
  (
    'How much did I pay Example Grocers this month?',
    AskIntent.spent,
    SlotKind.payee,
    'Example Grocers',
  ),
  (
    'how much to Example Grocers',
    AskIntent.spent,
    SlotKind.payee,
    'Example Grocers',
  ),
  (
    'How much did I spend at Example Grocers?',
    AskIntent.spent,
    SlotKind.payee,
    'Example Grocers',
  ),
  ('How much came in this month?', AskIntent.received, null, null),
  ('money in this month', AskIntent.received, null, null),
  ('how much did I receive', AskIntent.received, null, null),
  ('income this month', AskIntent.received, null, null),
  ('how much did I get', AskIntent.received, null, null),
  ('How much did KCB send me?', AskIntent.receivedFrom, SlotKind.payee, 'KCB'),
  ('KCB sent me how much', AskIntent.receivedFrom, SlotKind.payee, 'KCB'),
  ('Money received from KCB', AskIntent.receivedFrom, SlotKind.payee, 'KCB'),
  (
    'Did Acme pay me last month?',
    AskIntent.receivedFrom,
    SlotKind.payee,
    'Acme',
  ),
  (
    'What has Example Sacco paid me?',
    AskIntent.receivedFrom,
    SlotKind.payee,
    'Example Sacco',
  ),
  (
    'How much did I receive from Acme?',
    AskIntent.receivedFrom,
    SlotKind.payee,
    'Acme',
  ),
  ('received from Acme', AskIntent.receivedFrom, SlotKind.payee, 'Acme'),
  (
    'How much did Acme send me?',
    AskIntent.receivedFrom,
    SlotKind.payee,
    'Acme',
  ),
  (
    'How much did I send to Example Landlord?',
    AskIntent.sentTo,
    SlotKind.payee,
    'Example Landlord',
  ),
  ("What's my M-Pesa balance?", AskIntent.balance, SlotKind.account, 'M-Pesa'),
  ("What's my Equity balance?", AskIntent.balance, SlotKind.account, 'Equity'),
  ('KCB account balance', AskIntent.balance, SlotKind.account, 'KCB'),
  (
    'How much did I pay in charges on KCB this month?',
    AskIntent.fees,
    SlotKind.account,
    'KCB',
  ),
  (
    'What was my biggest payment to Example Nowhere?',
    AskIntent.biggestPayment,
    SlotKind.payee,
    'Example Nowhere',
  ),
  (
    'How much do I owe to Example Lender?',
    AskIntent.debts,
    SlotKind.payee,
    'Example Lender',
  ),
  ("What's the weather?", AskIntent.outOfScope, null, null),
  ('What can I ask?', AskIntent.help, null, null),
];

/// Names the model does not tag as the case says, with the slot it gives
/// them instead (null: none). It reads "on KCB this month" as one period.
/// The rules find KCB, and the app goes by them here.
const _modelMisses = <String, SlotKind?>{
  'How much did I pay in charges on KCB this month?': null,
};

/// A reader that is never sure, so the model's reading stands on its own.
class _Unsure implements QuestionReader {
  const _Unsure();

  @override
  Understanding read(String question) =>
      const Understanding(AskIntent.outOfScope, confidence: 0);

  @override
  void close() {}
}

/// Replays the real model's recorded outputs, by the exact input the app
/// encodes for the question.
class _Replay implements AskReaderRuntime {
  _Replay(Map<String, Object?> recorded)
    : _readings = {
        for (final r in recorded['readings']! as List)
          (r as Map)['question'] as String: r.cast<String, Object?>(),
      };

  final Map<String, Map<String, Object?>> _readings;
  final _missing = <String, List<int>>{};

  /// The question being read, so a missing recording can name it.
  String current = '';

  bool has(String question) => _readings.containsKey(question);

  @override
  (List<List<double>>, List<double>) run(List<int> input) {
    final r = _readings[current];
    if (r == null || !_sameInput(r['input']! as List, input)) {
      _missing[current] = input;
      // Unsure: the app falls back.
      return (
        [
          for (var t = 0; t < readerMaxTokens; t++)
            [1.0, for (var j = 1; j < 7; j++) 0.0],
        ],
        List<double>.filled(30, 1 / 30),
      );
    }
    final slots = [
      for (final row in r['slots']! as List)
        [for (final p in row as List) (p as num).toDouble()],
    ];
    final width = slots.isEmpty ? 7 : slots.first.length;
    return (
      [
        ...slots,
        for (var t = slots.length; t < readerMaxTokens; t++)
          [1.0, for (var j = 1; j < width; j++) 0.0],
      ],
      [for (final p in r['intent']! as List) (p as num).toDouble()],
    );
  }

  static bool _sameInput(List<Object?> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// With `ASK_READER_RECORD=path`, writes the questions with no recording
  /// for tool/ask_reader_decodes.py.
  void saveMissing() {
    final path = Platform.environment['ASK_READER_RECORD'];
    if (path == null) return;
    File(path).writeAsStringSync(
      jsonEncode([
        for (final MapEntry(key: question, value: input) in _missing.entries)
          {
            'question': question,
            'input': input,
            'tokens': input.take(readerMaxTokens).where((id) => id != 0).length,
          },
      ]),
    );
  }

  @override
  void close() {}
}
