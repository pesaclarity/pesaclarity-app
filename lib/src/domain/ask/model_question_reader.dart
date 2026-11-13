import '../reader/reader_tokens.dart';
import 'understanding.dart';

/// Runs `ask-reader.tflite`: the message reader's input encoding
/// ([encodeTokens], `[2 * readerMaxTokens]` int32) in; per-token slot label
/// probabilities and intent probabilities out.
abstract interface class AskReaderRuntime {
  /// `([readerMaxTokens][slot labels], [intents])`.
  (List<List<double>>, List<double>) run(List<int> input);

  void close();
}

/// `ask-reader-manifest.json` as pesaclarity-ml will write it. The fields
/// mirror the message reader's manifest; the exact spec is not settled, so
/// anything this app does not understand makes it fall back to the rules.
class AskReaderManifest {
  const AskReaderManifest({
    required this.modelFile,
    required this.modelSha256,
    required this.modelSizeBytes,
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
      schemaVersion: json['reader_schema_version']! as int,
      maxTokens: json['max_tokens']! as int,
      hashBuckets: json['hash_buckets']! as int,
      slotLabels: labels('slots'),
      intentLabels: labels('intent'),
    );
  }

  final String modelFile;
  final String modelSha256;
  final int modelSizeBytes;
  final int schemaVersion;
  final int maxTokens;
  final int hashBuckets;

  /// `other`, then BIO labels such as `B-category`, `I-category`.
  final List<String> slotLabels;

  /// [AskIntent.label]s in output order.
  final List<String> intentLabels;

  /// Why this model cannot be used by this app; empty when it can.
  List<String> incompatibilities() => [
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

SlotKind? _slotOf(String label) {
  final dash = label.indexOf('-');
  if (dash < 0) return null;
  return SlotKind.values.asNameMap()[label.substring(dash + 1)];
}

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
    final tokens = tokenise(question);
    final List<List<double>> slots;
    final List<double> intents;
    try {
      (slots, intents) = _runtime.run(encodeTokens(tokens));
    } on Object {
      return fallback.read(question);
    }
    var best = 0;
    for (var i = 1; i < intents.length; i++) {
      if (intents[i] > intents[best]) best = i;
    }
    if (intents.isEmpty || intents[best] < minConfidence) {
      return fallback.read(question);
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
    return Understanding(intent, confidence: intents[best], spans: spans);
  }

  @override
  void close() {
    _runtime.close();
    fallback.close();
  }
}
