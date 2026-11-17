import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/ask/model_question_reader.dart';
import 'package:pesaclarity/src/domain/ask/rule_question_reader.dart';
import 'package:pesaclarity/src/domain/ask/understanding.dart';
import 'package:pesaclarity/src/domain/ml/dart_ask_reader.dart';
import 'package:pesaclarity/src/domain/ml/plain_weights.dart';
import 'package:pesaclarity/src/domain/reader/reader_tokens.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/ask/data/ask_model_store.dart';

/// The bundled ask reader on the phrasings the first one got wrong (#238,
/// #240): counts and sums for one payee, "how much to X", money in, "X sent
/// me", account balances and names the app has never seen. The model runs
/// here as in the app, in Dart from `ask-reader.weights`, first alone and
/// then with the rules behind it.
///
/// TFLite stays the reference: tool/ask_reader_decodes.py ran the same
/// model's `ask-reader.tflite` on these very inputs, and the Dart reader must
/// give the same labels and probabilities within [_tolerance].
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
  final readings = {
    for (final r
        in (recorded['readings']! as List).cast<Map<String, Object?>>())
      r['question'] as String: r.cast<String, Object?>(),
  };
  final missing = <String>[];
  tearDownAll(() => _saveMissing(missing));

  test('the recordings and the weights are of the bundled reader', () async {
    final manifest = (jsonDecode(
      utf8.decode((await asset('$askModelFolder/$askReaderManifestFile'))!),
    ) as Map).cast<String, Object?>();
    expect(recorded['model_sha256'], manifest['model_sha256']);
    final weights = PlainWeights.parse(
      (await asset('$askModelFolder/${manifest['weights_file']}'))!,
    );
    expect(weights.sourceSha256, manifest['model_sha256']);
  });

  test('the Dart reader gives TFLite\'s outputs on every recording', () async {
    final model = DartAskReader.parse(
      (await asset('$askModelFolder/ask-reader.weights'))!,
    );
    var worst = 0.0;
    for (final r in readings.values) {
      final input = (r['input']! as List).cast<int>();
      final (slots, intent) = model.run(input);
      final wantIntent = _doubles(r['intent']!);
      expect(
        _argmax(intent),
        _argmax(wantIntent),
        reason: 'intent of "${r['question']}"',
      );
      worst = math.max(worst, _maxDiff(intent, wantIntent));
      final wantSlots = (r['slots']! as List).map(_doubles).toList();
      for (final (t, want) in wantSlots.indexed) {
        expect(
          _argmax(slots[t]),
          _argmax(want),
          reason: 'slot of token $t of "${r['question']}"',
        );
        worst = math.max(worst, _maxDiff(slots[t], want));
      }
    }
    expect(readings, hasLength(greaterThanOrEqualTo(_cases.length)));
    expect(worst, lessThan(_tolerance));
  });

  Future<QuestionReader> reader(QuestionReader fallback) => loadAskReader(
    readAsset: asset,
    openRuntime: DartAskReader.parse,
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
          final input = encodeTokens(tokenise(question));
          final recording = readings[question];
          if (recording == null ||
              !_same((recording['input']! as List).cast<int>(), input)) {
            missing.add(question);
          }
          expect(
            missing,
            isNot(contains(question)),
            reason: 'no TFLite recording: run tool/ask_reader_decodes.py',
          );
          final u = r.read(question);
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

  test('off the UI thread, the reading is the same', () async {
    final r = await reader(
      RuleQuestionReader(today: () => CalendarDate(2026, 11, 16)),
    ) as ModelQuestionReader;
    for (final (question, _, _, _) in _cases) {
      final here = r.read(question);
      final there = await r.readInBackground(question);
      expect(there.intent, here.intent, reason: question);
      expect(there.spans, here.spans, reason: question);
      expect(there.confidence, here.confidence, reason: question);
    }
  });
}

/// How far the Dart reader's probabilities may be from TFLite's. The
/// recordings round to 1e-5; the reader is about 4e-5 off, as TFLite's own
/// kernels (XNNPACK and the built-in ones) are from each other.
const _tolerance = 1e-4;

List<double> _doubles(Object? values) => [
  for (final v in values! as List) (v! as num).toDouble(),
];

int _argmax(List<double> v) {
  var best = 0;
  for (var i = 1; i < v.length; i++) {
    if (v[i] > v[best]) best = i;
  }
  return best;
}

double _maxDiff(List<double> a, List<double> b) {
  expect(a.length, b.length);
  var worst = 0.0;
  for (var i = 0; i < a.length; i++) {
    worst = math.max(worst, (a[i] - b[i]).abs());
  }
  return worst;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// With `ASK_READER_RECORD=path`, writes the questions with no recording
/// for tool/ask_reader_decodes.py.
void _saveMissing(List<String> questions) {
  final path = Platform.environment['ASK_READER_RECORD'];
  if (path == null) return;
  File(path).writeAsStringSync(
    jsonEncode([
      for (final question in questions.toSet())
        if (encodeTokens(tokenise(question)) case final input)
          {
            'question': question,
            'input': input,
            'tokens': input.take(readerMaxTokens).where((id) => id != 0).length,
          },
    ]),
  );
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
