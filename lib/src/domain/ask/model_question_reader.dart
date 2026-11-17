import 'dart:isolate';

import '../ml/plain_weights.dart';
import '../reader/reader_tokens.dart';
import 'matcher.dart';
import 'rule_question_reader.dart';
import 'understanding.dart';

/// Runs the Ask reader: the message reader's input encoding ([encodeTokens],
/// `[2 * readerMaxTokens]` int32) in; per-token slot label probabilities and
/// intent probabilities out. The app's is `DartAskReader`, on the model's
/// plain weights.
abstract interface class AskReaderRuntime {
  /// `([readerMaxTokens][slot labels], [intents])`.
  (List<List<double>>, List<double>) run(List<int> input);

  void close();
}

/// `ask-reader-manifest.json` as pesaclarity-ml writes it (its docs/ASK.md
/// and docs/WEIGHTS.md). Anything this app does not understand makes it
/// fall back to the rules.
class AskReaderManifest {
  const AskReaderManifest({
    required this.modelFile,
    required this.modelSha256,
    required this.modelSizeBytes,
    required this.weightsFile,
    required this.weightsSha256,
    required this.weightsSizeBytes,
    required this.weightsFormatVersion,
    required this.schemaVersion,
    required this.maxTokens,
    required this.hashBuckets,
    required this.slotLabels,
    required this.intentLabels,
  });

  factory AskReaderManifest.fromJson(Map<String, Object?> json) {
    final outputs = json['outputs']! as Map<String, Object?>;
    List<String> labels(String name) =>
        ((outputs[name]! as Map<String, Object?>)['labels']! as List)
            .cast<String>();
    return AskReaderManifest(
      modelFile: json['model_file']! as String,
      modelSha256: json['model_sha256']! as String,
      modelSizeBytes: json['model_size_bytes']! as int,
      weightsFile: json['weights_file']! as String,
      weightsSha256: json['weights_sha256']! as String,
      weightsSizeBytes: json['weights_size_bytes']! as int,
      weightsFormatVersion: json['weights_format_version']! as int,
      schemaVersion: json['reader_schema_version']! as int,
      maxTokens: json['max_tokens']! as int,
      hashBuckets: json['hash_buckets']! as int,
      slotLabels: labels('slots'),
      intentLabels: labels('intent'),
    );
  }

  /// The TFLite file pesaclarity-ml exported and scored. The app does not
  /// ship it; its hash says which model the weights are.
  final String modelFile;
  final String modelSha256;
  final int modelSizeBytes;

  /// The model's plain weights (pesaclarity-ml docs/WEIGHTS.md), read out
  /// of [modelFile]: what the app runs.
  final String weightsFile;
  final String weightsSha256;
  final int weightsSizeBytes;
  final int weightsFormatVersion;
  final int schemaVersion;
  final int maxTokens;
  final int hashBuckets;

  /// `other`, then one label per slot such as `category` (BIO labels such
  /// as `B-category` are read too).
  final List<String> slotLabels;

  /// [AskIntent.label]s in output order.
  final List<String> intentLabels;

  /// Why this model cannot be used by this app; empty when it can.
  List<String> incompatibilities() => [
    if (weightsFormatVersion != plainWeightsFormatVersion)
      'weights format $weightsFormatVersion, app reads '
          '$plainWeightsFormatVersion',
    if (schemaVersion != readerSchemaVersion)
      'token schema $schemaVersion, app reads $readerSchemaVersion',
    if (maxTokens != readerMaxTokens) 'max tokens $maxTokens',
    if (hashBuckets != readerHashBuckets) 'hash buckets $hashBuckets',
    for (final l in intentLabels)
      if (AskIntent.fromLabel(l) == null) 'unknown intent $l',
    for (final l in slotLabels)
      if (l != 'other' && _slotOf(l) == null) 'unknown slot label $l',
  ];
}

/// The slot a label tags: plain (`category`, as pesaclarity-ml exports
/// them) or BIO (`B-category`, `I-category`). Null for `other`.
SlotKind? _slotOf(String label) =>
    SlotKind.values.asNameMap()[label.substring(label.indexOf('-') + 1)];

/// The trained question reader. Falls back to [fallback] when unsure.
class ModelQuestionReader implements QuestionReader {
  ModelQuestionReader(
    this._runtime,
    this._manifest, {
    required this.fallback,
    this.minConfidence = 0.5,
  });

  final AskReaderRuntime _runtime;
  final AskReaderManifest _manifest;
  final QuestionReader fallback;
  final double minConfidence;

  @override
  Understanding read(String question) {
    final rules = _rules(question);
    if (rules != null && RuleQuestionReader.decides(question, rules)) {
      return rules;
    }
    final tokens = tokenise(question);
    final (List<List<double>>, List<double>) outputs;
    try {
      outputs = _runtime.run(encodeTokens(tokens));
    } on Object {
      return rules ?? fallback.read(question);
    }
    return _reading(question, tokens, outputs, rules);
  }

  /// [read], with the model run in a background isolate, so its several
  /// milliseconds (tens on a slow phone) never hold up the UI thread. The
  /// isolate gets a copy of the runtime; nothing is loaded again.
  Future<Understanding> readInBackground(String question) async {
    final rules = _rules(question);
    if (rules != null && RuleQuestionReader.decides(question, rules)) {
      return rules;
    }
    final tokens = tokenise(question);
    final (List<List<double>>, List<double>) outputs;
    try {
      outputs = await _runInIsolate(_runtime, encodeTokens(tokens));
    } on Object {
      return rules ?? fallback.read(question);
    }
    return _reading(question, tokens, outputs, rules);
  }

  // Not async, and static: the closure must hold the runtime and the input
  // only, not this reader or anything else alive in an async method.
  static Future<(List<List<double>>, List<double>)> _runInIsolate(
    AskReaderRuntime runtime,
    List<int> input,
  ) => Isolate.run(() => runtime.run(input));

  Understanding? _rules(String question) =>
      fallback is RuleQuestionReader ? fallback.read(question) : null;

  /// The reading from the model's [outputs] for [question]'s [tokens], with
  /// the [rules]' reading as the safety net.
  Understanding _reading(
    String question,
    List<MessageToken> tokens,
    (List<List<double>>, List<double>) outputs,
    Understanding? rules,
  ) {
    final (slots, intents) = outputs;
    var best = 0;
    for (var i = 1; i < intents.length; i++) {
      if (intents[i] > intents[best]) best = i;
    }
    if (intents.isEmpty || intents[best] < minConfidence) {
      return rules ?? fallback.read(question);
    }
    final intent =
        AskIntent.fromLabel(_manifest.intentLabels[best]) ??
        AskIntent.outOfScope;

    // Join B-/I- runs into spans.
    final spans = <AskSpan>[];
    SlotKind? open;
    int? start;
    var end = 0;
    void close() {
      if (open != null && start != null) {
        spans.add(AskSpan(open!, question.substring(start!, end), start!, end));
      }
      open = null;
      start = null;
    }

    for (var t = 0; t < tokens.length && t < slots.length; t++) {
      final row = slots[t];
      var label = 0;
      for (var j = 1; j < row.length; j++) {
        if (row[j] > row[label]) label = j;
      }
      final name = _manifest.slotLabels[label];
      final kind = _slotOf(name);
      if (kind == null) {
        close();
        continue;
      }
      if (name.startsWith('B-') || kind != open) {
        close();
        open = kind;
        start = tokens[t].start;
      }
      end = tokens[t].end;
    }
    close();
    final read = Understanding(intent, confidence: intents[best], spans: spans);
    // The first model was taught on a few made-up names and left most real
    // ones untagged: "How many times did I pay Example Grocers?" came back
    // with no payee, so Ask counted every payment. The current one is
    // taught on thousands of invented names and tags them, but a name it
    // misses still means it has misread the question, and its intent too:
    // when the rules find a name the model did not, the rules' reading
    // stands. A safety net.
    if (rules != null && rules.intent.isLookup && _missesName(read, rules)) {
      return rules;
    }
    return read;
  }

  /// Whether [rules] found a name (a payee, category, account or item)
  /// that none of [model]'s spans covers.
  static bool _missesName(Understanding model, Understanding rules) {
    const names = {
      SlotKind.payee,
      SlotKind.category,
      SlotKind.account,
      SlotKind.item,
    };
    final tagged = [
      for (final s in model.spans)
        if (names.contains(s.kind)) normaliseName(s.text),
    ];
    for (final s in rules.spans) {
      if (!names.contains(s.kind)) continue;
      final name = normaliseName(s.text);
      if (name.isEmpty) continue;
      if (!tagged.any((t) => t.contains(name) || name.contains(t))) {
        return true;
      }
    }
    return false;
  }

  @override
  void close() {
    _runtime.close();
    fallback.close();
  }
}
