import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/ask/model_reply_writer.dart';
import 'package:pesaclarity/src/domain/ask/reply_writer.dart';

/// The writer contract from pesaclarity-ml (docs/ASK.md) and the checks
/// that keep every figure, name and date the app's own.
void main() {
  final manifest = AskWriterManifest.fromJson(
    (jsonDecode(
      File('assets/models/ask/ask-writer-manifest.json').readAsStringSync(),
    ) as Map).cast<String, Object?>(),
  );
  final cases = jsonDecode(
    File('test/fixtures/ask/ask_writer_cases.v1.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final ids = {for (final (i, t) in manifest.vocab.indexed) t: i};
  List<String> words(String text) => [
    for (final m in RegExp(
      r"\{[a-z_]+\}|[a-z']+|[.,!?:]",
    ).allMatches(text.toLowerCase()))
      m.group(0)!,
  ];

  group('contract', () {
    test('detokenises as pesaclarity-ml does', () {
      for (final c in cases['detokenise']! as List) {
        final m = c as Map;
        expect(
          detokenise((m['tokens'] as List).cast<String>()),
          m['text'],
          reason: '${m['tokens']}',
        );
      }
    });

    test('checks replies as pesaclarity-ml does', () {
      for (final c in cases['checker']! as List) {
        final m = c as Map;
        final reason = writerCheck(
          m['template'] as String,
          given: (m['given'] as List).cast<String>().toSet(),
          required: manifest.required[m['kind']]!,
        );
        expect(reason, m['reason'], reason: '${m['template']}');
      }
    });

    test('writes fact tokens in the canonical order, with their ids', () {
      final writer = ModelReplyWriter(_Script.never(), manifest);
      for (final c in cases['fallbacks']! as List) {
        final m = c as Map;
        final facts = (m['facts'] as List).cast<String>();
        final w = WriterFacts(
          facts.first.substring('kind='.length),
          flags: {
            for (final f in facts.skip(1))
              if (!f.startsWith('{')) f,
          },
          // Out of order on purpose: the writer puts them in order.
          given: {
            for (final f in facts.reversed)
              if (f.startsWith('{')) f.substring(1, f.length - 1),
          },
        );
        final tokens = writer.factTokens(w);
        expect(tokens, facts);
        expect([for (final t in tokens) ids[t]], m['fact_ids']);
      }
    });

    test('draws the same numbers as tool/ask_writer_decodes.py', () {
      // Values printed by the tool's WriterRandom for the same seeds.
      final expected = {
        0: [0.31659353361465037, 0.8757069851271808, 0.4833001629449427],
        12345: [0.593402051134035, 0.5195978025440127, 0.8607330680824816],
        -7: [0.31676332652568817, 0.01623897417448461, 0.45964807248674333],
      };
      for (final MapEntry(:key, :value) in expected.entries) {
        final r = WriterRandom(key);
        expect([r.next(), r.next(), r.next()], value);
      }
    });
  });

  group('guard', () {
    final writer = ModelReplyWriter(_Script.never(), manifest);
    const balance = WriterFacts('balance', given: {'amount', 'account'});
    final values = <String, Object>{'amount': -130000, 'account': 'M-Pesa'};

    String? template(String reply, [WriterFacts facts = balance]) =>
        writer.checkedTemplate(words(reply), facts, values);

    test('a reply of words and given placeholders passes', () {
      expect(
        template('your {account} balance is {amount} .'),
        'Your {account} balance is {amount}.',
      );
    });

    test('the writer count is the app number', () {
      const debts = WriterFacts('debts', given: {'amount', 'count'});
      expect(
        writer.checkedTemplate(
          words('you owe {amount} across {count} loans .'),
          debts,
          {'amount': 500, 'number': '2', 'count': '2 debts'},
        ),
        'You owe {amount} across {number} loans.',
      );
    });

    test('anything that could change a figure, name or date fails', () {
      final bad = {
        // A placeholder it was not given.
        'you paid {payee} {amount} .': 'not_given',
        // The figure twice, or not at all.
        'you have {amount} , that is {amount} .': 'repeated',
        'your balance is low .': 'missing',
        // A category or a day the facts did not name.
        'you have {amount} for food .': 'names',
        'your balance today is {amount} .': 'names',
      };
      for (final MapEntry(:key, :value) in bad.entries) {
        expect(
          writerReplyProblem(
            words(key),
            balance,
            required: manifest.required['balance']!,
          ),
          value,
          reason: key,
        );
        expect(template(key), isNull, reason: key);
      }
    });

    test('empty, unended, too long or not plain text fails', () {
      expect(writer.checkedTemplate(const [], balance, values), isNull);
      expect(writer.checkedTemplate(null, balance, values), isNull);
      expect(
        writer.checkedTemplate(
          [...words('you have {amount} .'), for (var i = 0; i < 50; i++) 'so'],
          balance,
          values,
        ),
        isNull,
      );
      for (final stray in ['<unk>', 'kind=balance', 'cmp=more', '7', 'KES']) {
        expect(
          writer.checkedTemplate(
            ['you', 'have', '{amount}', stray, '.'],
            balance,
            values,
          ),
          isNull,
          reason: stray,
        );
      }
    });

    test('talk may name example questions; records may not', () {
      const help = WriterFacts('help');
      expect(
        writer.checkedTemplate(
          words('try : how much did i spend on food last month ?'),
          help,
          const {},
        ),
        'Try: how much did I spend on food last month?',
      );
    });

    test('nothing found names what was asked about', () {
      const nodata = WriterFacts(
        'nodata',
        given: {'period', 'category'},
        anyOf: {'category'},
      );
      final v = <String, Object>{'period': 'last month', 'category': 'food'};
      expect(
        writer.checkedTemplate(
          words('i found nothing for {category} {period} .'),
          nodata,
          v,
        ),
        'I found nothing for {category} {period}.',
      );
      expect(
        writer.checkedTemplate(
          words('no records for {period} yet .'),
          nodata,
          v,
        ),
        isNull,
      );
    });

    test('a value the app does not have is never asked for', () {
      // No account value: the account placeholder is dropped, not filled
      // with nothing.
      final ready = writer.prepare(balance, {'amount': 5});
      expect(ready!.given, {'amount'});
      // No amount: balance cannot be worded at all.
      expect(writer.prepare(balance, {'account': 'M-Pesa'}), isNull);
    });
  });

  group('decoding', () {
    test('masks what can never be right', () {
      final eos = manifest.eos;
      final amount = ids['{amount}']!;
      final payee = ids['{payee}']!;
      final have = ids['have']!;
      // The model wants <eos> first, then {payee}, then {amount} twice.
      final script = _Script([
        {eos: 9, have: 5},
        {payee: 9, amount: 5},
        {amount: 9, eos: 1},
        {amount: 9, eos: 5},
      ], manifest.vocab.length);
      final out = decodeReply(
        script.logits,
        WriterDecode(
          prefix: [ids['kind=balance']!, amount, manifest.sep],
          eos: eos,
          vocabSize: manifest.vocab.length,
          banned: [payee],
          once: [amount],
          needed: [amount],
          temperature: 0.01,
        ),
      );
      expect([for (final i in out!) manifest.vocab[i]], ['have', '{amount}']);
    });

    test('no <eos> before the end is no reply', () {
      final have = ids['have']!;
      final out = decodeReply(
        _Script([
          {have: 9},
        ], manifest.vocab.length).logits,
        WriterDecode(
          prefix: [ids['kind=hi']!, manifest.sep],
          eos: manifest.eos,
          vocabSize: manifest.vocab.length,
          banned: const [],
          once: const [],
          needed: const [],
        ),
      );
      expect(out, isNull);
    });

    test('a forced bad decode falls back to the template', () async {
      // With masking off the model writes {payee}, which balance was not
      // given: the checker refuses it and the template stays.
      final payee = ids['{payee}']!;
      final eos = manifest.eos;
      final writer = ModelReplyWriter(
        _Script([
          {ids['you']!: 9},
          {ids['paid']!: 9},
          {payee: 9},
          {ids['{amount}']!: 9},
          {eos: 9},
        ], manifest.vocab.length),
        manifest,
        mask: false,
      );
      final t = await writer.word(
        const WriterFacts('balance', given: {'amount'}),
        {'amount': -130000},
      );
      expect(t, isNull);
      expect((writer.asked, writer.worded), (1, 0));
    });

    test('a failing runtime falls back to the template', () async {
      final writer = ModelReplyWriter(_Script.failing(), manifest);
      expect(
        await writer.word(const WriterFacts('balance', given: {'amount'}), {
          'amount': 1,
        }),
        isNull,
      );
    });
  });

  group('filler openers', () {
    final writer = ModelReplyWriter(_Script.never(), manifest);
    const fees = WriterFacts('fees', given: {'amount', 'period'});
    final values = <String, Object>{'amount': 4287, 'period': 'this month'};

    String? template(String reply) =>
        writer.checkedTemplate(words(reply), fees, values);

    test('come off the start of a reply, which starts with a capital', () {
      expect(
        template('here it is . you paid {amount} in charges {period} .'),
        'You paid {amount} in charges {period}.',
      );
      expect(
        template('looking at it , you paid {amount} in charges {period} .'),
        'You paid {amount} in charges {period}.',
      );
      expect(
        template('here you go ! {amount} went on charges {period} .'),
        '{amount} went on charges {period}.',
      );
      // One after another.
      expect(
        template('one moment , okay . you paid {amount} {period} .'),
        'You paid {amount} {period}.',
      );
    });

    test('are matched whatever the case, and only at the start', () {
      expect(stripOpeners('HERE IT IS. You paid 5.'), 'You paid 5.');
      expect(stripOpeners('Here You Go: done.'), 'Done.');
      expect(
        stripOpeners('You paid {amount}. Here it is.'),
        'You paid {amount}. Here it is.',
      );
      // A word that only starts like one, or one with no mark after it.
      expect(stripOpeners('Okayish week.'), 'Okayish week.');
      expect(stripOpeners('Sure enough, it rose.'), 'Sure enough, it rose.');
    });

    test('a reply that is only filler is no reply', () {
      expect(template('here it is .'), isNull);
    });

    test('no template sentence starts with one', () {
      final opener = RegExp(
        '^(?:${fillerOpeners.map(RegExp.escape).join('|')})[.,!:]',
        caseSensitive: false,
      );
      for (final t in TemplateReplyWriter.templates.values.expand((t) => t)) {
        expect(opener.hasMatch(t), isFalse, reason: t);
        expect(stripOpeners(t), t);
      }
    });
  });

  test('the bundled lists match what this app writes', () {
    expect(manifest.incompatibilities(), isEmpty);
    expect(replyPlaceholders, containsAll({'prev_amount', 'list', 'number'}));
    for (final p in writerPlaceholders) {
      expect(replyPlaceholders, contains(appFactFor(p)));
    }
  });
}

/// Logits from a script: step i gives the scores in steps[i] (the last
/// step repeats), every other token far below.
class _Script implements AskWriterRuntime {
  _Script(this.steps, this.vocab) : fail = false;

  _Script.never() : steps = const [], vocab = 0, fail = false;

  _Script.failing() : steps = const [], vocab = 0, fail = true;

  final List<Map<int, double>> steps;
  final int vocab;
  final bool fail;
  int _step = 0;

  List<double> logits(Int32List tokens, int position) {
    final s = steps[_step < steps.length ? _step : steps.length - 1];
    _step++;
    return [for (var i = 0; i < vocab; i++) s[i] ?? -20];
  }

  @override
  Future<List<int>?> decode(WriterDecode request) async {
    if (fail) throw StateError('no model');
    _step = 0;
    return decodeReply(logits, request);
  }

  @override
  void close() {}
}
