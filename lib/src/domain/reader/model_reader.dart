import '../ml/plain_weights.dart' show plainWeightsFormatVersion;
import 'message_reading.dart';
import 'reader_tokens.dart';

/// Runs the reader network on one encoded message.
abstract interface class ReaderRuntime {
  /// Label probabilities per token (`[readerMaxTokens][labels]`) and for the
  /// whole message (`[kinds]`).
  (List<List<double>>, List<double>) run(List<int> input);

  void close();
}

/// A [ReaderRuntime] that can also run several messages off the UI thread.
abstract interface class BackgroundReaderRuntime implements ReaderRuntime {
  /// [run] for each of [inputs], in a background isolate.
  Future<List<(List<List<double>>, List<double>)>> runAllInBackground(
    List<List<int>> inputs,
  );
}

/// `reader-manifest.json` as pesaclarity-ml writes it (docs/READER.md).
class ReaderManifest {
  const ReaderManifest({
    required this.weightsFile,
    required this.weightsSha256,
    required this.weightsSizeBytes,
    required this.weightsFormatVersion,
    required this.schemaVersion,
    required this.maxTokens,
    required this.hashBuckets,
    required this.fieldLabels,
    required this.kindLabels,
  });

  factory ReaderManifest.fromJson(Map<String, Object?> json) {
    final outputs = json['outputs']! as Map<String, Object?>;
    List<String> labels(String name) =>
        ((outputs[name]! as Map<String, Object?>)['labels']! as List)
            .cast<String>();
    return ReaderManifest(
      weightsFile: json['weights_file']! as String,
      weightsSha256: json['weights_sha256']! as String,
      weightsSizeBytes: json['weights_size_bytes']! as int,
      weightsFormatVersion: json['weights_format_version']! as int,
      schemaVersion: json['reader_schema_version']! as int,
      maxTokens: json['max_tokens']! as int,
      hashBuckets: json['hash_buckets']! as int,
      fieldLabels: labels('fields'),
      kindLabels: labels('kind'),
    );
  }

  static const _fields = [
    'other',
    'amount',
    'counterparty',
    'date',
    'time',
    'balance',
    'reference',
    'fee',
  ];
  static const _kinds = ['money_out', 'money_in', 'not_transaction'];

  /// The model's plain weights with rayo's graph (pesaclarity-ml
  /// docs/WEIGHTS.md), a file beside the manifest, with its SHA-256 and size.
  final String weightsFile;
  final String weightsSha256;
  final int weightsSizeBytes;
  final int weightsFormatVersion;
  final int schemaVersion;
  final int maxTokens;
  final int hashBuckets;
  final List<String> fieldLabels;
  final List<String> kindLabels;

  /// Why this app cannot feed or read the model; empty when it can.
  List<String> incompatibilities() => [
    if (schemaVersion != readerSchemaVersion)
      'reader schema $schemaVersion, app implements $readerSchemaVersion',
    if (weightsFormatVersion != plainWeightsFormatVersion)
      'weights format $weightsFormatVersion, app reads '
          '$plainWeightsFormatVersion',
    if (maxTokens != readerMaxTokens) 'max_tokens $maxTokens',
    if (hashBuckets != readerHashBuckets) 'hash_buckets $hashBuckets',
    if (fieldLabels.join(',') != _fields.join(',')) 'field labels $fieldLabels',
    if (kindLabels.join(',') != _kinds.join(',')) 'kind labels $kindLabels',
  ];
}

/// The trained reader.
class ModelMessageReader implements MessageReader {
  ModelMessageReader(this._runtime);

  final ReaderRuntime _runtime;

  @override
  MessageReading read(String message) {
    final tokens = tokenise(message);
    final (fields, kind) = _runtime.run(encodeTokens(tokens));
    return decodeReading(message, tokens, fields, kind);
  }

  /// What the reader makes of each of [messages], off the UI thread when
  /// the runtime can run there.
  Future<List<MessageReading>> readAll(List<String> messages) async {
    final runtime = _runtime;
    if (runtime is! BackgroundReaderRuntime || messages.isEmpty) {
      return [for (final m in messages) read(m)];
    }
    final tokens = [for (final m in messages) tokenise(m)];
    final outputs = await runtime.runAllInBackground([
      for (final t in tokens) encodeTokens(t),
    ]);
    return [
      for (var i = 0; i < messages.length; i++)
        decodeReading(messages[i], tokens[i], outputs[i].$1, outputs[i].$2),
    ];
  }

  @override
  void close() => _runtime.close();
}

/// What [reader] makes of each of [messages]: off the UI thread for the
/// trained reader, where its runtime can run there.
Future<List<MessageReading>> readMessages(
  MessageReader reader,
  List<String> messages,
) async => reader is ModelMessageReader
    ? reader.readAll(messages)
    : [for (final m in messages) reader.read(m)];
