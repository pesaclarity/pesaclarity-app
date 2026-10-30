import 'message_reading.dart';
import 'reader_tokens.dart';

/// Runs the reader network on one encoded message.
abstract interface class ReaderRuntime {
  /// Label probabilities per token (`[readerMaxTokens][labels]`) and for the
  /// whole message (`[kinds]`).
  (List<List<double>>, List<double>) run(List<int> input);

  void close();
}

/// `reader-manifest.json` as pesaclarity-ml writes it.
class ReaderManifest {
  const ReaderManifest({
    required this.modelFile,
    required this.modelSha256,
    required this.modelSizeBytes,
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
      modelFile: json['model_file']! as String,
      modelSha256: json['model_sha256']! as String,
      modelSizeBytes: json['model_size_bytes']! as int,
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

  final String modelFile;
  final String modelSha256;
  final int modelSizeBytes;
  final int schemaVersion;
  final int maxTokens;
  final int hashBuckets;
  final List<String> fieldLabels;
  final List<String> kindLabels;

  /// Why this app cannot feed or read the model; empty when it can.
  List<String> incompatibilities() => [
    if (schemaVersion != readerSchemaVersion)
      'reader schema $schemaVersion, app implements $readerSchemaVersion',
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

  @override
  void close() => _runtime.close();
}
