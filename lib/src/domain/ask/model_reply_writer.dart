import 'dart:math' show exp;
import 'dart:typed_data';

import 'reply_writer.dart';

// The ask writer from pesaclarity-ml (`akili ask-writer`), as its
// docs/ASK.md specifies it: fact tokens in, one reply token out per step,
// replies made only of words and placeholders. The app fills the
// placeholders from its own answer, so the writer chooses wording only.

/// The Ask contract version this app implements.
const askSchemaVersion = 1;

/// Tokens the writer reads and writes at once: facts, `<sep>`, the reply.
const writerLength = 64;

/// Reply tokens at most, `<eos>` not counted. The longest training replies
/// are about 42.
const writerMaxReplyTokens = 48;

/// Characters at most in a reply template, as the ml checker allows.
const writerMaxChars = 300;

/// The writer's reply kinds, in manifest order.
const writerReplyKinds = [
  'spent',
  'received',
  'sent_to',
  'received_from',
  'count_payments',
  'biggest_payment',
  'top_payees',
  'top_categories',
  'trend',
  'compare',
  'bills_due',
  'subscriptions',
  'debts',
  'lent',
  'safe_to_spend',
  'balance',
  'goals',
  'income_sources',
  'sales',
  'top_items',
  'profit',
  'low_stock',
  'who_owes_me',
  'fees',
  'nodata',
  'clarify',
  'out_of_scope',
  'hi',
  'thanks',
  'bye',
  'help',
];

/// The writer's flags, in canonical fact order.
const writerFlags = [
  'cmp=more',
  'cmp=less',
  'cmp=same',
  'level=peak',
  'level=low',
  'count=one',
  'state=ok',
  'state=tight',
  'state=over',
  'state=done',
  'result=loss',
];

/// The writer's placeholders, in canonical fact order.
const writerPlaceholders = [
  'amount',
  'prev_amount',
  'target',
  'change',
  'percent',
  'count',
  'days',
  'category',
  'payee',
  'item',
  'account',
  'goal',
  'period',
  'prev_period',
  'date',
  'name',
  'list',
];

const _specialTokens = ['<pad>', '<unk>', '<sep>', '<eos>'];
const _punctuation = {'.', ',', '!', '?', ':'};

/// Kinds that only talk: their sentences may name example questions
/// ("how much did I spend on food last month?"), which hold no facts.
const _talkKinds = {'clarify', 'out_of_scope', 'hi', 'thanks', 'bye', 'help'};

/// Words that would name a category, a person or a day the facts did not
/// give. A reply about records never uses them; only the app's values do.
const _namingWords = {
  'food',
  'transport',
  'school',
  'mum',
  'today',
  'tomorrow',
  'yesterday',
  'week',
  'payday',
};

/// The app's fact key for a writer placeholder. The writer's `{count}` is a
/// bare number ("3"); the app's own `count` is a phrase ("3 payments").
String appFactFor(String placeholder) =>
    placeholder == 'count' ? 'number' : placeholder;

/// What the writer is asked to word: one of [writerReplyKinds], the flags
/// that hold and the placeholders it may use.
class WriterFacts {
  const WriterFacts(
    this.kind, {
    this.flags = const {},
    this.given = const {},
    this.anyOf = const {},
  });

  final String kind;
  final Set<String> flags;

  /// Writer placeholder names, such as `amount` and `count`.
  final Set<String> given;

  /// When not empty, the reply must use at least one of these, on top of
  /// what the kind requires: "nothing for {category}", not "no records".
  final Set<String> anyOf;

  @override
  String toString() => 'kind=$kind ${flags.join(' ')} ${given.join(' ')}';
}

/// `ask-writer-manifest.json` as pesaclarity-ml writes it.
class AskWriterManifest {
  const AskWriterManifest({
    required this.modelFile,
    required this.modelSha256,
    required this.modelSizeBytes,
    required this.schemaVersion,
    required this.length,
    required this.vocabSize,
    required this.specialTokens,
    required this.replyKinds,
    required this.flags,
    required this.placeholders,
    required this.required,
    required this.allowedFlags,
    required this.allowedPlaceholders,
    required this.vocab,
    required this.inputShape,
    required this.outputShape,
    this.temperature = 0.8,
  });

  factory AskWriterManifest.fromJson(Map<String, Object?> json) {
    List<String> strings(Object? v) => (v! as List).cast<String>();
    Map<String, List<String>> lists(Object? v) => {
      for (final e in (v! as Map).entries) e.key as String: strings(e.value),
    };
    List<int> shape(String name) =>
        ((json[name]! as Map)['shape']! as List).cast<int>();
    final special = (json['special_tokens']! as Map).cast<String, int>();
    final decoding = json['decoding'] as Map?;
    return AskWriterManifest(
      modelFile: json['model_file']! as String,
      modelSha256: json['model_sha256']! as String,
      modelSizeBytes: json['model_size_bytes']! as int,
      schemaVersion: json['ask_schema_version']! as int,
      length: json['length']! as int,
      vocabSize: json['vocab_size']! as int,
      specialTokens: [
        special['pad']!,
        special['unk']!,
        special['sep']!,
        special['eos']!,
      ],
      replyKinds: strings(json['reply_kinds']),
      flags: strings(json['flags']),
      placeholders: strings(json['placeholders']),
      required: lists(json['required']),
      allowedFlags: lists(json['allowed_flags']),
      allowedPlaceholders: lists(json['allowed_placeholders']),
      vocab: strings(json['vocab']),
      inputShape: shape('input'),
      outputShape: shape('output'),
      temperature: (decoding?['temperature'] as num?)?.toDouble() ?? 0.8,
    );
  }

  final String modelFile;
  final String modelSha256;
  final int modelSizeBytes;
  final int schemaVersion;
  final int length;
  final int vocabSize;

  /// Ids of `<pad>`, `<unk>`, `<sep>` and `<eos>`.
  final List<int> specialTokens;
  final List<String> replyKinds;
  final List<String> flags;
  final List<String> placeholders;

  /// Per kind, the placeholders a reply must use.
  final Map<String, List<String>> required;
  final Map<String, List<String>> allowedFlags;
  final Map<String, List<String>> allowedPlaceholders;

  /// Token ids are positions in this list.
  final List<String> vocab;
  final List<int> inputShape;
  final List<int> outputShape;
  final double temperature;

  int get sep => specialTokens[2];
  int get eos => specialTokens[3];

  /// Why this model cannot be used by this app; empty when it can.
  List<String> incompatibilities() {
    bool same<T>(List<T> a, List<T> b) =>
        a.length == b.length &&
        [for (var i = 0; i < a.length; i++) i].every((i) => a[i] == b[i]);
    final ids = {for (final (i, t) in vocab.indexed) t: i};
    return [
      if (schemaVersion != askSchemaVersion)
        'ask schema $schemaVersion, app reads $askSchemaVersion',
      if (length != writerLength) 'length $length',
      if (vocab.length != vocabSize) 'vocab of ${vocab.length}, not $vocabSize',
      if (!same(inputShape, [1, writerLength])) 'input shape $inputShape',
      if (!same(outputShape, [1, writerLength, vocabSize]))
        'output shape $outputShape',
      for (var i = 0; i < _specialTokens.length; i++)
        if (specialTokens[i] != i ||
            vocab.length <= i ||
            vocab[i] != _specialTokens[i])
          'special token ${_specialTokens[i]}',
      if (!same(replyKinds, writerReplyKinds)) 'reply kinds differ',
      if (!same(flags, writerFlags)) 'flags differ',
      if (!same(placeholders, writerPlaceholders)) 'placeholders differ',
      for (final k in writerReplyKinds) ...[
        if (!ids.containsKey('kind=$k')) 'no token kind=$k',
        for (final p in required[k] ?? const <String>[])
          if (!(allowedPlaceholders[k] ?? const []).contains(p))
            '$k requires $p but does not allow it',
      ],
      for (final f in writerFlags)
        if (!ids.containsKey(f)) 'no token $f',
      for (final p in writerPlaceholders)
        if (!ids.containsKey('{$p}')) 'no token {$p}',
      for (final t in vocab.skip(_specialTokens.length))
        if (!_vocabToken.hasMatch(t)) 'token "$t" is not a word',
    ];
  }
}

final _vocabToken = RegExp(
  r"^([a-z']+|[.,!?:]|\{[a-z_]+\}|kind=[a-z_]+|[a-z]+=[a-z]+)$",
);

/// One decode, plain values only so it can cross to another isolate.
class WriterDecode {
  const WriterDecode({
    required this.prefix,
    required this.eos,
    required this.vocabSize,
    required this.banned,
    required this.once,
    required this.needed,
    this.temperature = 0.8,
    this.seed = 0,
    this.length = writerLength,
    this.maxReply = writerMaxReplyTokens,
    this.mask = true,
  });

  /// Fact ids then `<sep>`.
  final List<int> prefix;
  final int eos;
  final int vocabSize;

  /// Ids never written: special and fact tokens, placeholders not given.
  final List<int> banned;

  /// Placeholder ids: each written at most once.
  final List<int> once;

  /// Placeholder ids the reply must hold before `<eos>`.
  final List<int> needed;
  final double temperature;
  final int seed;
  final int length;
  final int maxReply;

  /// Off only in tests, to see the checker catch what masking would stop.
  final bool mask;
}

/// Next-token logits after [position] of [tokens] (`[length]` ids, padded
/// with 0). The model is causal, so padding after [position] does not
/// change them.
typedef WriterLogits = List<double> Function(Int32List tokens, int position);

/// Draws in [0, 1) from a seed: xorshift32, so the same seed gives the same
/// reply on every phone, and tool/ask_writer_decodes.py can repeat a decode.
class WriterRandom {
  WriterRandom(int seed) : _state = _start(seed);

  int _state;

  static int _start(int seed) {
    final s = (seed ^ 0x9E3779B9) & 0xffffffff;
    return s == 0 ? 1 : s;
  }

  double next() {
    var x = _state;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    _state = x;
    return x / 4294967296.0;
  }
}

/// Decodes a reply with [logits] as docs/ASK.md says: sample from the
/// softmax at [WriterDecode.temperature] (seeded, so the same question
/// words the same way), stop at `<eos>`. Tokens that can never be right are
/// masked out first. Null when no `<eos>` came in time.
List<int>? decodeReply(WriterLogits logits, WriterDecode d) {
  if (d.prefix.length >= d.length) return null;
  final tokens = Int32List(d.length)..setAll(0, d.prefix);
  var n = d.prefix.length;
  final rng = WriterRandom(d.seed);
  final banned = d.banned.toSet();
  final once = d.once.toSet();
  final needed = d.needed.toSet();
  final out = <int>[];
  final weights = Float64List(d.vocabSize);
  while (n < d.length && out.length <= d.maxReply) {
    final row = logits(tokens, n - 1);
    if (row.length != d.vocabSize) {
      throw StateError('expected ${d.vocabSize} logits, got ${row.length}');
    }
    var best = double.negativeInfinity;
    for (var i = 0; i < row.length; i++) {
      final masked =
          d.mask &&
          (banned.contains(i) ||
              (once.contains(i) && out.contains(i)) ||
              (i == d.eos && !needed.every(out.contains)));
      final v = masked || !row[i].isFinite
          ? double.negativeInfinity
          : row[i] / d.temperature;
      weights[i] = v;
      if (v > best) best = v;
    }
    if (best == double.negativeInfinity) return null;
    var total = 0.0;
    for (var i = 0; i < weights.length; i++) {
      final w = weights[i] == double.negativeInfinity
          ? 0.0
          : exp(weights[i] - best);
      weights[i] = w;
      total += w;
    }
    var pick = rng.next() * total;
    var next = -1;
    for (var i = 0; i < weights.length; i++) {
      if (weights[i] <= 0) continue;
      next = i;
      pick -= weights[i];
      if (pick <= 0) break;
    }
    if (next == d.eos) return out;
    out.add(next);
    tokens[n++] = next;
  }
  return null;
}

/// Runs `ask-writer.tflite`.
abstract interface class AskWriterRuntime {
  /// Reply token ids for [request], or null when none ended in time.
  Future<List<int>?> decode(WriterDecode request);

  void close();
}

/// Join reply tokens into a template, as docs/ASK.md says.
String detokenise(List<String> tokens) {
  final out = StringBuffer();
  var capital = true;
  for (final tok in tokens) {
    if (_punctuation.contains(tok)) {
      out.write(tok);
      if (tok == '.' || tok == '!' || tok == '?') capital = true;
      continue;
    }
    var word = tok;
    if (!tok.startsWith('{')) {
      if (capital || tok == 'i' || tok.startsWith("i'")) {
        word = tok[0].toUpperCase() + tok.substring(1);
      }
    }
    capital = false;
    if (out.isNotEmpty) out.write(' ');
    out.write(word);
  }
  return out.toString();
}

final _placeholderInText = RegExp(r'\{([a-z_]+)\}');

/// The ml checker on a detokenised template: '' when it passes, else the
/// first failed rule (`empty`, `digit`, `stray`, `repeated`, `not_given`,
/// `missing`).
String writerCheck(
  String template, {
  required Set<String> given,
  required List<String> required,
}) {
  if (template.trim().isEmpty || template.length > writerMaxChars) {
    return 'empty';
  }
  if (RegExp('[0-9]').hasMatch(template)) return 'digit';
  final names = [
    for (final m in _placeholderInText.allMatches(template)) m.group(1)!,
  ];
  final rest = template.replaceAll(_placeholderInText, '');
  if (RegExp('[<>={}]').hasMatch(rest)) return 'stray';
  if (names.toSet().length != names.length) return 'repeated';
  if (names.any((n) => !given.contains(n))) return 'not_given';
  if (required.any((r) => !names.contains(r))) return 'missing';
  return '';
}

/// Why a decoded reply cannot be shown, or '' when it can. Runs on the
/// tokens whatever the decoder masked, so a bad decode always falls back.
String writerReplyProblem(
  List<String>? tokens,
  WriterFacts facts, {
  required List<String> required,
}) {
  if (tokens == null) return 'no_eos';
  if (tokens.isEmpty) return 'empty';
  if (tokens.length > writerMaxReplyTokens) return 'long';
  for (final t in tokens) {
    if (_specialTokens.contains(t) ||
        t.startsWith('kind=') ||
        writerFlags.contains(t)) {
      return 'stray';
    }
    if (!_replyToken.hasMatch(t)) return 'stray';
    if (!_talkKinds.contains(facts.kind) && _namingWords.contains(t)) {
      return 'names';
    }
  }
  final template = detokenise(tokens);
  if (!_plainText.hasMatch(template)) return 'stray';
  final check = writerCheck(template, given: facts.given, required: required);
  if (check.isEmpty &&
      facts.anyOf.isNotEmpty &&
      !facts.anyOf.any((p) => template.contains('{$p}'))) {
    return 'missing';
  }
  return check;
}

/// Openers that say nothing ("Here it is.", "Looking at it,"), taken off
/// the start of a decoded reply. Lower case, as the writer's words are.
const fillerOpeners = [
  'here it is',
  'here you go',
  'here you are',
  "here's what i found",
  'looking at it',
  'looking at this',
  'looking at your records',
  'let me see',
  "let's see",
  'let me check',
  'one moment',
  'okay',
  'ok',
  'alright',
  'all right',
  'sure',
  'so',
];

final _opener = RegExp(
  '^(?:${fillerOpeners.map(RegExp.escape).join('|')})\\s*[.,!:]\\s*',
  caseSensitive: false,
);

/// [reply] without the [fillerOpeners] it starts with, one after another
/// ("One moment, okay. ..."), and with a capital again. An opener counts
/// only when a mark follows it, so "Sure enough, it rose." stays.
String stripOpeners(String reply) {
  var text = reply.trimLeft();
  for (
    var m = _opener.firstMatch(text);
    m != null;
    m = _opener.firstMatch(text)
  ) {
    text = text.substring(m.end);
  }
  if (text.isEmpty || text.startsWith('{')) return text;
  return text[0].toUpperCase() + text.substring(1);
}

final _replyToken = RegExp(r"^([a-z']+|[.,!?:]|\{[a-z_]+\})$");
final _plainText = RegExp(r"^[A-Za-z' .,!?:{}_]+$");

/// The trained writer: words a reply from [WriterFacts], or says it cannot
/// so the template stays.
class ModelReplyWriter {
  ModelReplyWriter(this._runtime, this.manifest, {this.mask = true})
    : _ids = {for (final (i, t) in manifest.vocab.indexed) t: i};

  final AskWriterRuntime _runtime;
  final AskWriterManifest manifest;
  final Map<String, int> _ids;

  /// Masking of impossible tokens while decoding; off only in tests.
  final bool mask;

  /// How many replies were asked for and how many were worded, since open.
  int asked = 0;
  int worded = 0;

  /// The facts as the writer reads them, cut to what [kind] allows and
  /// [values] holds. Null when a required placeholder has no value.
  WriterFacts? prepare(WriterFacts facts, Map<String, Object> values) {
    final kind = facts.kind;
    if (!manifest.replyKinds.contains(kind)) return null;
    final allowed = manifest.allowedPlaceholders[kind] ?? const [];
    final flags = manifest.allowedFlags[kind] ?? const [];
    final given = {
      for (final p in facts.given)
        if (allowed.contains(p) && _hasValue(values[appFactFor(p)])) p,
    };
    final required = manifest.required[kind] ?? const [];
    if (!required.every(given.contains)) return null;
    final anyOf = facts.anyOf.intersection(given);
    if (facts.anyOf.isNotEmpty && anyOf.isEmpty) return null;
    return WriterFacts(
      kind,
      flags: {
        for (final f in facts.flags)
          if (flags.contains(f)) f,
      },
      given: given,
      anyOf: anyOf,
    );
  }

  /// The fact tokens in canonical order.
  List<String> factTokens(WriterFacts facts) => [
    'kind=${facts.kind}',
    for (final f in manifest.flags)
      if (facts.flags.contains(f)) f,
    for (final p in manifest.placeholders)
      if (facts.given.contains(p)) '{$p}',
  ];

  /// An app template for [facts] (placeholders named as [values]' keys),
  /// or null to keep the template sentence.
  Future<String?> word(
    WriterFacts facts,
    Map<String, Object> values, {
    int seed = 0,
  }) async {
    asked++;
    final ready = prepare(facts, values);
    if (ready == null) return null;
    final required = manifest.required[ready.kind] ?? const [];
    final prefix = [for (final t in factTokens(ready)) _ids[t]!, manifest.sep];
    final placeholderIds = {
      for (final p in manifest.placeholders) p: _ids['{$p}']!,
    };
    final List<int>? ids;
    try {
      ids = await _runtime.decode(
        WriterDecode(
          prefix: prefix,
          eos: manifest.eos,
          vocabSize: manifest.vocab.length,
          banned: [
            for (final (i, t) in manifest.vocab.indexed)
              if (i != manifest.eos &&
                  (_specialTokens.contains(t) ||
                      t.startsWith('kind=') ||
                      manifest.flags.contains(t) ||
                      (t.startsWith('{') &&
                          !ready.given.contains(
                            t.substring(1, t.length - 1),
                          )) ||
                      (!_talkKinds.contains(ready.kind) &&
                          _namingWords.contains(t))))
                i,
          ],
          once: [for (final p in ready.given) placeholderIds[p]!],
          needed: [for (final p in required) placeholderIds[p]!],
          temperature: manifest.temperature,
          seed: seed,
          mask: mask,
        ),
      );
    } on Object {
      return null;
    }
    final tokens = ids == null
        ? null
        : [
            for (final i in ids)
              if (i >= 0 && i < manifest.vocab.length)
                manifest.vocab[i]
              else
                '<unk>',
          ];
    final template = checkedTemplate(tokens, ready, values);
    if (template != null) worded++;
    return template;
  }

  /// [tokens] as an app template when every check passes, else null.
  String? checkedTemplate(
    List<String>? tokens,
    WriterFacts facts,
    Map<String, Object> values,
  ) {
    final required = manifest.required[facts.kind] ?? const [];
    if (writerReplyProblem(tokens, facts, required: required).isNotEmpty) {
      return null;
    }
    final template = stripOpeners(detokenise(tokens!)).replaceAllMapped(
      _placeholderInText,
      (m) => '{${appFactFor(m.group(1)!)}}',
    );
    // The app's own check: known placeholders with values, no digits.
    if (!checkTemplate(template, values.keys.toSet())) return null;
    return template;
  }

  void close() => _runtime.close();
}

bool _hasValue(Object? v) => switch (v) {
  null => false,
  final String s => s.trim().isNotEmpty,
  _ => true,
};
