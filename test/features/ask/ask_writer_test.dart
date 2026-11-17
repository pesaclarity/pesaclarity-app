import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/ask/answer.dart';
import 'package:pesaclarity/src/domain/ask/context.dart';
import 'package:pesaclarity/src/domain/ask/model_reply_writer.dart';
import 'package:pesaclarity/src/domain/ask/reply_writer.dart';
import 'package:pesaclarity/src/features/ask/application/ask_providers.dart';
import 'package:pesaclarity/src/features/ask/data/ask_model_store.dart';
import 'package:pesaclarity/src/features/ask/data/rayo_ask_runtimes.dart';
import 'package:pesaclarity/src/features/balances/application/balances_providers.dart';
import 'package:pesaclarity/src/shared/widgets/amounts_hidden.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';
import '../balances/balances_harness.dart';

/// The bundled ask writer, and Ask's replies worded by it on the synthetic
/// scenario. The model runs here as in the app, on rayo (its build hook
/// compiles the C for the host), through the app's own checks.
///
/// TFLite stays the reference: tool/ask_writer_decodes.py decoded these very
/// requests with the model's `ask-writer.tflite`, and every reply rayo
/// writes for a recorded request must be TFLite's, token for token.
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

  Future<AskWriterManifest> manifest() async => AskWriterManifest.fromJson(
    (jsonDecode(
      utf8.decode((await asset('$askModelFolder/$askWriterManifestFile'))!),
    ) as Map).cast<String, Object?>(),
  );

  final recorded = jsonDecode(
    File('test/fixtures/ask/ask_writer_decodes.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final reference = _Reference(recorded);
  tearDownAll(reference.saveMissing);
  tearDownAll(
    // ignore: avoid_print
    () => print("rayo wrote TFLite's reply ${reference.same} times"),
  );
  AskWriterRuntime real(Uint8List bytes, AskWriterManifest manifest) =>
      _Checked(openAskWriter(bytes, manifest), reference);

  String filled(AskAnswer a) => fillTemplate(
    a.template,
    a.facts,
    money: (minor) => moneyOrHidden(minor, hidden: false, withCurrency: false),
  );

  bool isTemplate(AskAnswer a) =>
      TemplateReplyWriter.templates[a.kind]?.contains(a.template) ?? false;

  test('the recordings are of the bundled writer', () async {
    expect(recorded['model_sha256'], (await manifest()).modelSha256);
  });

  group('the synthetic scenario', () {
    late AppDatabase db;
    late ScenarioAccounts ids;
    late ProviderContainer c;

    setUp(() async {
      db = openTestDatabase();
      ids = await seedScenario(db);
      c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => scenarioNow),
          askReaderRuntimeOpenerProvider.overrideWithValue(null),
          askWriterRuntimeOpenerProvider.overrideWithValue(real),
        ],
      );
      addTearDown(c.dispose);
      addTearDown(db.close);
    });

    Future<AskAnswer> ask(String question) async {
      final engine = await c.read(askEngineProvider.future);
      return (await engine.ask(
        question,
        context: AskContext.empty,
        now: scenarioNow,
      )).answer;
    }

    test(
      "the M-Pesa balance is exactly the journal's, below zero in words",
      () async {
        final answer = await ask("what's my M-Pesa balance");
        final overview = await c.read(balancesOverviewProvider.future);
        final mpesa = overview.byId(ids.mpesa)!;
        expect(answer.figureMinor, kes(-1300));
        expect(answer.figureMinor, mpesa.heldMinor);
        // The sentence shows the amount without a sign and says "below zero".
        expect(answer.facts['amount'], -mpesa.heldMinor);
        // The writer has no words for below zero, so the template says it.
        expect(answer.kind, ReplyKind.accountOwesFuliza);
        expect(isTemplate(answer), isTrue, reason: answer.template);
        final text = filled(answer);
        expect(text, "M-Pesa is 1,300 below zero: that's what you owe Fuliza.");
        expect(RegExp('1,300').allMatches(text), hasLength(1), reason: text);
        // No other number in it, and no minus sign.
        expect(text.replaceAll('1,300', '').contains(RegExp('[0-9]')), isFalse);
        expect(text.contains(RegExp(r'[-\u2212]\s*[0-9]')), isFalse);
      },
    );

    test('the total below zero says so, Fuliza named', () async {
      final answer = await ask('How much money do I have?');
      final overview = await c.read(balancesOverviewProvider.future);
      expect(answer.figureMinor, overview.totalMinor('KES'));
      expect(filled(answer), "You're 1,150 below zero once Fuliza is counted.");
    });

    test('no writer reply starts with a filler opener', () async {
      for (final question in _questions) {
        for (final ending in _endings) {
          final text = filled(await ask('$question$ending'));
          expect(
            RegExp(
              '^(?:${fillerOpeners.map(RegExp.escape).join('|')})[.,!:]',
              caseSensitive: false,
            ).hasMatch(text),
            isFalse,
            reason: text,
          );
          expect(text, isNot(contains('the 0 of')));
          expect(text, isNot(contains(': 0.')));
          expect(
            text.toLowerCase(),
            isNot(contains('category this month was not sorted')),
          );
        }
      }
    });

    test(
      '"How much did KCB send me?" is money moved from KCB, not spending',
      () async {
        final answer = await ask('How much did KCB send me?');
        expect(answer.kind, ReplyKind.ownTransfers);
        expect(answer.figureMinor, kes(3920));
        expect(
          filled(answer),
          'KCB sent 3,920 to your other accounts this month. That is your own '
          'money moving, so it is not counted as money in.',
        );
        expect(answer.rows.single.title, 'M-Pesa');
      },
    );

    test(
      'every reply keeps the figures, names and dates it was given',
      () async {
        final writer = (await c.read(modelReplyWriterProvider.future))!;
        final samples = <String>[];
        for (final question in _questions) {
          for (final ending in _endings) {
            final answer = await ask('$question$ending');
            final text = filled(answer);
            // Every value in the sentence is one of the answer's, and the
            // sentence has no number of its own.
            var rest = text;
            for (final p in [
              for (final m in RegExp(
                r'\{([a-z_]+)\}',
              ).allMatches(answer.template))
                m.group(1)!,
            ]) {
              final v = answer.facts[p]!;
              final shown = v is int && moneyPlaceholders.contains(p)
                  ? moneyOrHidden(v, hidden: false, withCurrency: false)
                  : '$v';
              expect(
                rest.toLowerCase().contains(shown.toLowerCase()),
                isTrue,
                reason: '$shown in $text',
              );
              rest = rest.replaceFirst(
                RegExp(RegExp.escape(shown), caseSensitive: false),
                '',
              );
            }
            expect(rest.contains(RegExp('[0-9]')), isFalse, reason: text);
            expect(text.length, lessThanOrEqualTo(300));
            if (ending.isEmpty) {
              samples.add(
                '$question -> $text'
                '${isTemplate(answer) ? '  [template]' : ''}',
              );
            }
          }
        }
        // ignore: avoid_print
        print(
          'ask writer: worded ${writer.worded} of ${writer.asked} '
          '(${_percent(writer.worded, writer.asked)}); '
          '${writer.asked - writer.worded} fell back to templates\n'
          '${samples.join('\n')}',
        );
        // The model words nearly every reply it is asked for.
        expect(
          writer.worded,
          greaterThanOrEqualTo((writer.asked * 0.9).floor()),
        );
      },
    );

    test('charts and "Ask about this" are as they were', () async {
      final trend = await ask('Is my spending going up?');
      expect(trend.chart, isNotNull);
      expect(trend.kind, ReplyKind.trend);
      final grocers = await ask('How much did I spend at Example Grocers?');
      expect(grocers.link, AskLink.activity);
      expect(grocers.rows, isNotEmpty);
    });
  });

  group('without the writer', () {
    Future<AskAnswer> balance(List<Override> overrides) async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await seedScenario(db);
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => scenarioNow),
          askReaderRuntimeOpenerProvider.overrideWithValue(null),
          ...overrides,
        ],
      );
      addTearDown(c.dispose);
      expect(await c.read(modelReplyWriterProvider.future), isNull);
      final engine = await c.read(askEngineProvider.future);
      return (await engine.ask(
        "what's my M-Pesa balance",
        context: AskContext.empty,
        now: scenarioNow,
      )).answer;
    }

    Future<Uint8List?> Function(String) withAsset(
      String name,
      Uint8List? Function(Uint8List bytes) change,
    ) => (path) async {
      final bytes = await asset(path);
      return path.endsWith(name) && bytes != null ? change(bytes) : bytes;
    };

    Uint8List json(Map<String, Object?> Function(Map<String, Object?>) f) =>
        utf8.encode(
          jsonEncode(
            f(
              (jsonDecode(
                File('assets/models/ask/ask-writer-manifest.json')
                    .readAsStringSync(),
              ) as Map).cast(),
            ),
          ),
        );

    final cases = <String, List<Override>>{
      'there is no writer runtime': [
        askWriterRuntimeOpenerProvider.overrideWithValue(null),
      ],
      'the runtime cannot open the file': [
        askWriterRuntimeOpenerProvider.overrideWithValue(
          (bytes, manifest) => throw StateError('no runtime'),
        ),
      ],
      'the manifest is missing': [
        askAssetReaderProvider.overrideWithValue(
          withAsset(askWriterManifestFile, (_) => null),
        ),
        askWriterRuntimeOpenerProvider.overrideWithValue(real),
      ],
      'the manifest is not JSON': [
        askAssetReaderProvider.overrideWithValue(
          withAsset(askWriterManifestFile, (_) => utf8.encode('{"model')),
        ),
        askWriterRuntimeOpenerProvider.overrideWithValue(real),
      ],
      'the manifest is for another schema': [
        askAssetReaderProvider.overrideWithValue(
          withAsset(
            askWriterManifestFile,
            (_) => json((m) => {...m, 'ask_schema_version': 2}),
          ),
        ),
        askWriterRuntimeOpenerProvider.overrideWithValue(real),
      ],
      'the model file is missing': [
        askAssetReaderProvider.overrideWithValue(
          withAsset('ask-writer.weights', (_) => null),
        ),
        askWriterRuntimeOpenerProvider.overrideWithValue(real),
      ],
      'the model file is not the one in the manifest': [
        askAssetReaderProvider.overrideWithValue(
          withAsset(
            'ask-writer.weights',
            (b) => Uint8List.fromList(b)..[100] ^= 1,
          ),
        ),
        askWriterRuntimeOpenerProvider.overrideWithValue(real),
      ],
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test('Ask uses its templates when $key', () async {
        final answer = await balance(value);
        expect(answer.kind, ReplyKind.accountOwesFuliza);
        expect(answer.figureMinor, kes(-1300));
        expect(isTemplate(answer), isTrue, reason: answer.template);
      });
    }
  });

  test('a reply takes well under 150 ms on the host', () async {
    // The real model on rayo, from the facts to <eos>, on one core.
    final m = await manifest();
    final rayo = openAskWriter(
      (await asset('$askModelFolder/${m.weightsFile}'))!,
      m,
    );
    addTearDown(rayo.close);
    final model = ModelReplyWriter(rayo, m);
    final times = <double>[];
    for (var i = 0; i < 20; i++) {
      final sw = Stopwatch()..start();
      await model.word(
        const WriterFacts('balance', given: {'amount', 'account'}),
        {'amount': -130000, 'account': 'M-Pesa'},
        seed: i,
      );
      times.add(sw.elapsedMicroseconds / 1000);
    }
    times.sort();
    // ignore: avoid_print
    print('ask writer on rayo, per reply: median ${times[10]} ms');
    expect(times[10], lessThan(150));

    // The app's side of a reply (masking, sampling, checks) with the
    // writer's real sizes, and logits as cheap as can be.
    final writer = ModelReplyWriter(_Timed(m), m);
    final clock = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      await writer.word(
        const WriterFacts('balance', given: {'amount', 'account'}),
        {'amount': -130000, 'account': 'M-Pesa'},
        seed: i,
      );
    }
    final perReply = clock.elapsedMilliseconds / 20;
    // ignore: avoid_print
    print('the app side of a reply: $perReply ms');
    expect(perReply, lessThan(30));
  });
}

String _percent(int a, int b) =>
    b == 0 ? '-' : '${(a * 1000 / b).round() / 10}%';

/// Questions about the synthetic scenario, in the words people use.
const _questions = [
  "what's my M-Pesa balance",
  'How much money do I have?',
  'How much did I pay in charges this month?',
  'How much did I spend this month?',
  'What was my biggest payment this month?',
  'Who do I pay the most?',
  'Where does my money go?',
  'How much did I spend at Example Grocers?',
  'How many times did I pay Example Grocers this month?',
  'Did I spend more this month than last month?',
  'how often do I pay Example Grocers',
  'number of payments to Example Grocers',
  'times I paid Example Grocers this month',
  'How much did I pay Example Grocers this month?',
  'how much to Example Grocers',
  'How many times did I pay Zebra Hardware this month?',
  'How much came in this month?',
  'money in this month',
  'how much did I receive',
  'income this month',
  'how much did I get',
  'How much did KCB send me?',
  'How much did I send to Example Landlord?',
  'How much do I owe?',
  'What bills are due?',
  'What is safe to spend?',
  'Who owes me?',
  'How much did I spend on food last month?',
  'hi',
  'thanks',
  'bye',
  'what can you do',
  'should I buy bitcoin',
];

/// The same questions again, so each is worded from more than one seed.
const _endings = ['', '?', ' please', '!', ' pls', ' ?', '..', ' thanks?'];

/// TFLite's decodes of Ask's requests, recorded with the bundled model;
/// notes requests it lacks.
class _Reference {
  _Reference(Map<String, Object?> recorded)
    : _decodes = {
        for (final d in recorded['decodes']! as List)
          _key(
            (d as Map)['prefix'] as List,
            d['seed'] as int,
          ): switch (d['ids']) {
            final List<Object?> ids => ids.cast<int>(),
            _ => null,
          },
      };

  final Map<String, List<int>?> _decodes;
  final _missing = <String, WriterDecode>{};

  /// Replies checked against a recording, all the same.
  int same = 0;

  static String _key(List<Object?> prefix, int seed) =>
      '${prefix.join(',')}|$seed';

  /// Fails the test when [ids] are not TFLite's decode of [r].
  void check(WriterDecode r, List<int>? ids) {
    final key = _key(r.prefix, r.seed);
    if (!_decodes.containsKey(key)) {
      _missing[key] = r;
      return;
    }
    expect(ids, _decodes[key], reason: 'rayo and TFLite differ on $key');
    same++;
  }

  /// With `ASK_WRITER_RECORD=path`, writes the requests with no recording
  /// for tool/ask_writer_decodes.py.
  void saveMissing() {
    final path = Platform.environment['ASK_WRITER_RECORD'];
    if (path == null) return;
    File(path).writeAsStringSync(
      jsonEncode([
        for (final r in _missing.values)
          {
            'prefix': r.prefix,
            'seed': r.seed,
            'eos': r.eos,
            'vocab_size': r.vocabSize,
            'banned': r.banned,
            'once': r.once,
            'needed': r.needed,
            'temperature': r.temperature,
            'length': r.length,
            'max_reply': r.maxReply,
            'mask': r.mask,
          },
      ]),
    );
  }
}

/// The app's writer on rayo, each reply checked against [_Reference].
class _Checked implements AskWriterRuntime {
  _Checked(this._real, this._reference);

  final AskWriterRuntime _real;
  final _Reference _reference;

  @override
  Future<List<int>?> decode(WriterDecode r) async {
    final ids = await _real.decode(r);
    _reference.check(r, ids);
    return ids;
  }

  @override
  void close() => _real.close();
}

/// Flat logits of the writer's real size; ends the reply after the
/// required placeholder.
class _Timed implements AskWriterRuntime {
  _Timed(this.m);

  final AskWriterManifest m;

  @override
  Future<List<int>?> decode(WriterDecode r) async {
    final amount = m.vocab.indexOf('{amount}');
    final vocab = m.vocab.length;
    return decodeReply((tokens, position) {
      final row = List<double>.filled(vocab, 0);
      // A reply of about 20 words, then the amount, then <eos>.
      final step = position - r.prefix.length + 1;
      if (step >= 20) row[amount] = 30;
      if (step >= 21) row[m.eos] = 60;
      return row;
    }, r);
  }

  @override
  void close() {}
}
