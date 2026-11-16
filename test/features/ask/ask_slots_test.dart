import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/ask/answer.dart';
import 'package:pesaclarity/src/domain/ask/context.dart';
import 'package:pesaclarity/src/domain/ask/model_question_reader.dart';
import 'package:pesaclarity/src/domain/ask/reply_writer.dart';
import 'package:pesaclarity/src/domain/ask/understanding.dart';
import 'package:pesaclarity/src/domain/reader/reader_tokens.dart';
import 'package:pesaclarity/src/features/ask/application/ask_providers.dart';
import 'package:pesaclarity/src/features/ask/data/ask_model_store.dart';
import 'package:pesaclarity/src/features/insights/application/insights_providers.dart';
import 'package:pesaclarity/src/shared/widgets/amounts_hidden.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';
import '../balances/balances_harness.dart';

/// Ask answers the question asked on the synthetic scenario: a count for
/// one payee is that payee's, and money in is what Home and Insights call
/// income. Each question is asked with the rules alone and with a reader
/// that reads as the first bundled model did: run on these very questions with
/// TensorFlow (pesaclarity-ml dfb9c24), it tags no payee in any of them and
/// reads "how often do I pay X" as out of scope, "times I paid X" as help
/// and "how much did I pay X" as subscriptions.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The first bundled model's intent for each question, as it read them.
  const modelIntents = {
    'How many times did I pay Example Grocers this month?': 'count_payments',
    'how often do I pay Example Grocers': 'out_of_scope',
    'number of payments to Example Grocers': 'count_payments',
    'times I paid Example Grocers this month': 'help',
    'How much did I pay Example Grocers this month?': 'subscriptions',
    'how much to Example Grocers': 'help',
    'How much came in this month?': 'received',
    'money in this month': 'received',
    'how much did I receive': 'received',
    'income this month': 'received',
    'how much did I get': 'received',
    'How many times did I pay Zebra Hardware this month?': 'count_payments',
  };

  late AskReaderManifest manifest;
  setUpAll(() async {
    final data = await rootBundle.load(
      '$askModelFolder/$askReaderManifestFile',
    );
    manifest = AskReaderManifest.fromJson(
      (jsonDecode(utf8.decode(data.buffer.asUint8List())) as Map)
          .cast<String, Object?>(),
    );
  });

  String filled(AskAnswer a) => fillTemplate(
    a.template,
    a.facts,
    money: (minor) => moneyOrHidden(minor, hidden: false, withCurrency: false),
  );

  for (final withModel in [false, true]) {
    group(
      withModel ? 'read as the first bundled model did' : 'read by the rules',
      () {
        late AppDatabase db;
        late ProviderContainer c;
        final asked = <String>[];

        setUp(() async {
          db = openTestDatabase();
          await seedScenario(db);
          c = ProviderContainer(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              clockProvider.overrideWithValue(() => scenarioNow),
              askReaderRuntimeOpenerProvider.overrideWithValue(
                withModel
                    ? (_) => _AsBundled(manifest, modelIntents, asked)
                    : null,
              ),
              askWriterRuntimeOpenerProvider.overrideWithValue(null),
            ],
          );
          addTearDown(c.dispose);
          addTearDown(db.close);
        });

        Future<AskAnswer> ask(String question) async {
          asked.add(question);
          final engine = await c.read(askEngineProvider.future);
          return (await engine.ask(
            question,
            context: AskContext.empty,
            now: scenarioNow,
          )).answer;
        }

        test('the reader is the one this group is about', () async {
          final reader = await c.read(questionReaderProvider.future);
          expect(reader is ModelQuestionReader, withModel);
        });

        for (final q in [
          'How many times did I pay Example Grocers this month?',
          'how often do I pay Example Grocers',
          'number of payments to Example Grocers',
          'times I paid Example Grocers this month',
        ]) {
          test('"$q" is Example Grocers\' 2 payments, 2,400', () async {
            final a = await ask(q);
            expect(a.context.intent, AskIntent.countPayments);
            expect(a.kind, ReplyKind.count);
            expect(a.facts['number'], '2');
            expect(a.facts['amount'], kes(2400));
            expect(a.figureText, 'Twice');
            expect(a.rows.single.title, 'Example Grocers');
            expect(a.headline, 'Example Grocers · November 2026');
            final text = filled(a).toLowerCase();
            expect(text, contains('twice this month'));
            expect(text, contains('2,400'));
            expect(text, isNot(contains('12,307.13')));
          });
        }

        for (final q in [
          'How much did I pay Example Grocers this month?',
          'how much to Example Grocers',
        ]) {
          test('"$q" is what went to Example Grocers, 2,400', () async {
            final a = await ask(q);
            expect(a.figureMinor, kes(2400));
            expect(a.headline, 'Example Grocers · November 2026');
          });
        }

        test(
          'a payee not in the records is said, never every payment',
          () async {
            final a = await ask(
              'How many times did I pay Zebra Hardware this month?',
            );
            expect(a.kind, ReplyKind.noPaymentsTo);
            expect(a.figureMinor, isNull);
            expect(a.figureText, isNull);
            expect(
              filled(a),
              "I couldn't find payments to Zebra Hardware this month.",
            );
          },
        );

        for (final q in [
          'How much came in this month?',
          'money in this month',
          'how much did I receive',
          'income this month',
          'how much did I get',
        ]) {
          test('"$q" is money in as Insights counts it: none', () async {
            final a = await ask(q);
            expect(a.context.intent, AskIntent.received);
            // The only money in is KCB topping up M-Pesa, an own transfer,
            // and a Fuliza draw, which is borrowing: neither is income.
            final insights = await c.read(insightsSummaryProvider.future);
            expect(insights.current.incomeMinor, 0);
            expect(a.figureMinor, insights.current.incomeMinor);
            expect(a.kind, ReplyKind.nothingIn);
            expect(
              filled(a),
              'Nothing came in this month. The 3,920 that moved between your '
              "own accounts isn't counted as money in.",
            );
          });
        }
      },
    );
  }
}

/// Reads as the first bundled reader did on these questions: its intent, and no
/// payee or other name tagged.
class _AsBundled implements AskReaderRuntime {
  _AsBundled(this.manifest, this.intents, this.asked);

  final AskReaderManifest manifest;
  final Map<String, String> intents;

  /// The questions asked, last one last, to know which this run is for.
  final List<String> asked;

  @override
  (List<List<double>>, List<double>) run(List<int> input) {
    final intent = intents[asked.last] ?? 'out_of_scope';
    return (
      [
        for (var t = 0; t < readerMaxTokens; t++)
          [for (final l in manifest.slotLabels) l == 'other' ? 0.9 : 0.01],
      ],
      [for (final l in manifest.intentLabels) l == intent ? 0.9 : 0.01],
    );
  }

  @override
  void close() {}
}
