import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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
import 'package:pesaclarity/src/features/ask/data/rayo_ask_runtimes.dart';

/// The bundled ask reader on the phrasings the first one got wrong (#238,
/// #240), and those v2 got wrong (pesaclarity-ml#51): counts and sums for
/// one payee, "how much to X", money in, "X sent me", account balances,
/// fees on an account and names the app has never seen. The model runs
/// here as in the app, on rayo from `ask-reader.weights` (its build hook
/// compiles the C for the host), first alone and then with the rules behind
/// it.
///
/// tool/ask_reader_decodes.py ran the same file on the app's own rayo
/// library (the commit the app pins, as its build hook compiles it), on
/// these very inputs, and checked it against the PyTorch model it was
/// quantised from. The app's rayo must give those outputs bit for bit on
/// the platform they were recorded on, and the Dart reader (the fallback
/// where rayo cannot load) the same labels and probabilities within
/// [_dartTolerance].
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
  // Recordings of other weights are no recordings of these: every question
  // is then missing, for tool/ask_reader_decodes.py to record afresh.
  final bundled = jsonDecode(
    File('$askModelFolder/$askReaderManifestFile').readAsStringSync(),
  ) as Map<String, Object?>;
  final readings = {
    if (recorded['weights_sha256'] == bundled['weights_sha256'])
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
    expect(recorded['weights_sha256'], manifest['weights_sha256']);
    final weights = PlainWeights.parse(
      (await asset('$askModelFolder/${manifest['weights_file']}'))!,
    );
    expect(weights.sourceSha256, (manifest['source']! as Map)['sha256']);
  });

  // rayo gives the same floats on every kernel and thread count, and from
  // any compiler and flags (it is built with -ffp-contract=off). Another
  // platform's C library may round exp differently in the last bit, so
  // there only nearly.
  final exact = recorded['abi'] == Abi.current().toString();
  final runtimes = <String, (AskReaderRuntime Function(Uint8List), double)>{
    'rayo': (RayoAskReader.open, exact ? 0 : _otherPlatforms),
    'the Dart reader': (DartAskReader.parse, _dartTolerance),
  };
  for (final MapEntry(key: name, value: (open, tolerance))
      in runtimes.entries) {
    test(
      tolerance == 0
          ? '$name gives the recorded outputs bit for bit'
          : '$name gives the recorded outputs within $tolerance',
      () async {
        final model = open(
          (await asset('$askModelFolder/ask-reader.weights'))!,
        );
        addTearDown(model.close);
        var worst = 0.0;
        void check(List<double> got, List<double> want, String what) {
          if (tolerance == 0) {
            expect(got, want, reason: what);
          } else {
            expect(_argmax(got), _argmax(want), reason: what);
            worst = math.max(worst, _maxDiff(got, want));
          }
        }

        for (final r in readings.values) {
          final input = (r['input']! as List).cast<int>();
          final (slots, intent) = model.run(input);
          final question = r['question'];
          check(intent, _float32s(r['intent']!), 'intent of "$question"');
          final wantSlots = (r['slots']! as List).map(_float32s).toList();
          for (final (t, want) in wantSlots.indexed) {
            check(slots[t], want, 'slots of token $t of "$question"');
          }
        }
        expect(readings, hasLength(greaterThanOrEqualTo(_cases.length)));
        if (tolerance > 0) expect(worst, lessThan(tolerance));
      },
    );
  }

  test('the app opens the reader on rayo', () async {
    final model = openAskReader(
      (await asset('$askModelFolder/ask-reader.weights'))!,
    );
    addTearDown(model.close);
    expect(model, isA<RayoAskReader>());
  });

  Future<QuestionReader> reader(QuestionReader fallback) => loadAskReader(
    readAsset: asset,
    openRuntime: openAskReader,
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
            reason: 'no rayo recording: run tool/ask_reader_decodes.py',
          );
          final u = r.read(question);
          expect(u.intent, intent, reason: 'intent');
          if (kind != null) {
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

  test('the model alone reads the account and the period of fees', () async {
    final r = await reader(const _Unsure());
    final u = r.read('How much did I pay in charges on KCB this month?');
    expect(u.intent, AskIntent.fees);
    expect(u.span(SlotKind.account)?.text, 'KCB');
    expect(u.span(SlotKind.period)?.text, 'this month');
  });

  test('with the rules behind it, fees on an account are the model\'s '
      'reading', () async {
    final r = await reader(
      RuleQuestionReader(today: () => CalendarDate(2026, 11, 16)),
    );
    final u = r.read('How much did I pay in charges on KCB this month?');
    expect(u.intent, AskIntent.fees);
    expect(u.span(SlotKind.account)?.text, 'KCB');
    expect(u.span(SlotKind.period)?.text, 'this month');
    expect(u.span(SlotKind.payee), isNull);
  });

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

/// How far the app's rayo may be from the recordings on another platform
/// than theirs, whose C library may round exp in the last bit.
const _otherPlatforms = 1e-5;

/// How far the Dart reader's probabilities may be from rayo's. It runs each
/// operation as rayo does, in float32 (pesaclarity-ml docs/ASK.md), but
/// its softmax divides in double.
const _dartTolerance = 1e-4;

List<double> _float32s(Object? values) => Float32List.fromList([
  for (final v in values! as List) (v! as num).toDouble(),
]);

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
  // The misses of the reader before v3 (pesaclarity-ml#51).
  ('how much to john', AskIntent.spent, SlotKind.payee, 'john'),
  ('what did Naivas cost me', AskIntent.spent, SlotKind.payee, 'Naivas'),
  ('has Otieno paid me', AskIntent.receivedFrom, SlotKind.payee, 'Otieno'),
  ("What's the weather?", AskIntent.outOfScope, null, null),
  ('What can I ask?', AskIntent.help, null, null),
];

/// A reader that is never sure, so the model's reading stands on its own.
class _Unsure implements QuestionReader {
  const _Unsure();

  @override
  Understanding read(String question) =>
      const Understanding(AskIntent.outOfScope, confidence: 0);

  @override
  void close() {}
}
