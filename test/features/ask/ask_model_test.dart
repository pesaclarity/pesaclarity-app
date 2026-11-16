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
