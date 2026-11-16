import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/ask/model_question_reader.dart';
import 'package:pesaclarity/src/domain/ask/model_reply_writer.dart';
import 'package:pesaclarity/src/domain/ask/rule_question_reader.dart';
import 'package:pesaclarity/src/domain/ask/understanding.dart';
import 'package:pesaclarity/src/domain/reader/reader_tokens.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/ask/data/ask_model_store.dart';
import 'package:pesaclarity/src/features/categoriser/data/model_store.dart'
    show sha256Hex;

/// The bundled reader and writer, as pesaclarity-ml exports them, are ones
/// this app can use: their files match the manifests and every label and
/// token is known.
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

  Future<AskReaderManifest> manifest() async => AskReaderManifest.fromJson(
    (jsonDecode(
      utf8.decode((await asset('$askModelFolder/$askReaderManifestFile'))!),
    ) as Map).cast<String, Object?>(),
  );

  test('the bundled reader fits this app', () async {
    final m = await manifest();
    expect(m.incompatibilities(), isEmpty);
    expect(m.intentLabels, containsAll(['balance', 'fees']));
    final bytes = (await asset('$askModelFolder/${m.modelFile}'))!;
    expect(bytes.length, m.modelSizeBytes);
    expect(await sha256Hex(bytes), m.modelSha256);
    // The reader trained on invented names (pesaclarity-ml ask-reader v2),
    // which test/features/ask/ask_reader_test.dart replays.
    expect(m.modelSizeBytes, 271904);
    expect(
      m.modelSha256,
      'f6652fa718af71507e0cde8c6b2a635fcff69c7987aa439481d9106915740552',
    );
  });

  test('the bundled writer fits this app', () async {
    final m = AskWriterManifest.fromJson(
      (jsonDecode(
        utf8.decode((await asset('$askModelFolder/$askWriterManifestFile'))!),
      ) as Map).cast<String, Object?>(),
    );
    expect(m.incompatibilities(), isEmpty);
    final bytes = (await asset('$askModelFolder/${m.modelFile}'))!;
    expect(bytes.length, m.modelSizeBytes);
    expect(await sha256Hex(bytes), m.modelSha256);
    // The vocab: special tokens, the 31 kinds, 11 flags, 17 placeholders,
    // 5 marks, then lower-case words only. Not one digit.
    expect(m.vocab.length, 473);
    expect(m.vocab.take(4), ['<pad>', '<unk>', '<sep>', '<eos>']);
    expect(m.vocab.sublist(4, 35), [
      for (final k in writerReplyKinds) 'kind=$k',
    ]);
    expect(m.vocab.sublist(35, 46), writerFlags);
    expect(m.vocab.sublist(46, 63), [
      for (final p in writerPlaceholders) '{$p}',
    ]);
    expect(m.vocab.sublist(63, 68), ['.', ',', '!', '?', ':']);
    expect(
      m.vocab.skip(68).every((w) => RegExp(r"^[a-z']+$").hasMatch(w)),
      isTrue,
    );
  });

  test('the app opens the bundled reader and reads its labels', () async {
    final m = await manifest();
    final rules = RuleQuestionReader(today: () => CalendarDate(2026, 11, 16));
    const question = "what's my m-pesa balance";
    final tokens = tokenise(question);
    final runtime = _LabelRuntime(
      m,
      intent: 'balance',
      tags: {
        for (final (i, t) in tokens.indexed)
          if (t.start >= question.indexOf('m-pesa') &&
              t.end <= question.indexOf(' balance'))
            i: 'account',
      },
    );
    final reader = await loadAskReader(
      readAsset: asset,
      openRuntime: (_) => runtime,
      fallback: rules,
    );
    expect(reader, isA<ModelQuestionReader>());

    // The tokens of "m-pesa" are tagged `account`, a plain label.
    final u = reader.read(question);
    expect(u.intent, AskIntent.balance);
    expect(u.spans.single.kind, SlotKind.account);
    expect(u.spans.single.text, 'm-pesa');
  });

  test(
    'the rules decide money in from someone, whatever the model says',
    () async {
      final m = await manifest();
      final rules = RuleQuestionReader(today: () => CalendarDate(2026, 11, 16));
      // A model that reads everything as spending, sure of it.
      final reader = await loadAskReader(
        readAsset: asset,
        openRuntime: (_) => _LabelRuntime(m, intent: 'spent', tags: const {}),
        fallback: rules,
      );
      expect(reader, isA<ModelQuestionReader>());
      for (final (q, name) in [
        ('How much did KCB send me?', 'kcb'),
        ('What has Example Grocers paid me?', 'example grocers'),
        ('How much did I receive from Acme?', 'acme'),
        ('Money I got from Acme', 'acme'),
      ]) {
        final u = reader.read(q);
        expect(u.intent, AskIntent.receivedFrom, reason: q);
        expect(u.span(SlotKind.payee)?.text, name, reason: q);
      }
      // Other questions are still the model's.
      expect(reader.read('Where does my money go?').intent, AskIntent.spent);
    },
  );

  test(
    'a name the model leaves untagged is read by the rules, intent too',
    () async {
      final m = await manifest();
      final rules = RuleQuestionReader(today: () => CalendarDate(2026, 11, 16));
      // As the first bundled model read these: no payee tagged, and the intent
      // often wrong ("how often" out of scope, "how much did I pay"
      // subscriptions).
      for (final (q, modelIntent, intent) in [
        (
          'How many times did I pay Example Grocers this month?',
          'count_payments',
          AskIntent.countPayments,
        ),
        (
          'how often do I pay Example Grocers',
          'out_of_scope',
          AskIntent.countPayments,
        ),
        (
          'number of payments to Example Grocers',
          'count_payments',
          AskIntent.countPayments,
        ),
        (
          'times I paid Example Grocers this month',
          'help',
          AskIntent.countPayments,
        ),
        (
          'How much did I pay Example Grocers this month?',
          'subscriptions',
          AskIntent.spent,
        ),
        ('how much to Example Grocers', 'help', AskIntent.spent),
      ]) {
        final reader = await loadAskReader(
          readAsset: asset,
          openRuntime: (_) =>
              _LabelRuntime(m, intent: modelIntent, tags: const {}),
          fallback: rules,
        );
        final u = reader.read(q);
        expect(u.intent, intent, reason: q);
        expect(u.span(SlotKind.payee)?.text, 'example grocers', reason: q);
      }
    },
  );

  test('money in phrasings are money in, whatever the model says', () async {
    final m = await manifest();
    final reader = await loadAskReader(
      readAsset: asset,
      openRuntime: (_) => _LabelRuntime(m, intent: 'spent', tags: const {}),
      fallback: RuleQuestionReader(today: () => CalendarDate(2026, 11, 16)),
    );
    for (final q in [
      'How much came in this month?',
      'money in this month',
      'how much did I receive',
      'income this month',
      'how much did I get',
    ]) {
      expect(reader.read(q).intent, AskIntent.received, reason: q);
    }
    // Spending stays spending, salary or not.
    expect(
      reader.read('How much did I spend from my salary?').intent,
      AskIntent.spent,
    );
  });

  test('a name the model tags keeps the model\'s reading', () async {
    final m = await manifest();
    const q = 'How much did I send to John?';
    final john = tokenise(q).indexWhere((t) => t.text == 'John');
    final reader = await loadAskReader(
      readAsset: asset,
      openRuntime: (_) =>
          _LabelRuntime(m, intent: 'spent', tags: {john: 'payee'}),
      fallback: RuleQuestionReader(today: () => CalendarDate(2026, 11, 16)),
    );
    final u = reader.read(q);
    expect(u.intent, AskIntent.spent);
    expect(u.span(SlotKind.payee)?.text, 'John');
  });
}

/// Answers in the manifest's own label order, as the exported model does.
class _LabelRuntime implements AskReaderRuntime {
  _LabelRuntime(this.manifest, {required this.intent, required this.tags});

  final AskReaderManifest manifest;
  final String intent;

  /// Token index to slot label; every other token is `other`.
  final Map<int, String> tags;

  @override
  (List<List<double>>, List<double>) run(List<int> input) => (
    [
      for (var t = 0; t < readerMaxTokens; t++)
        [
          for (final l in manifest.slotLabels)
            l == (tags[t] ?? 'other') ? 0.9 : 0.01,
        ],
    ],
    [for (final l in manifest.intentLabels) l == intent ? 0.9 : 0.01],
  );

  @override
  void close() {}
}
