import '../ml/plain_weights.dart' show plainWeightsFormatVersion;
import 'features.dart' as features;
import 'features.dart' show FeatureConfig;

/// `model-manifest.json`, written next to every exported categoriser by
/// pesaclarity-ml (`akili.export.manifest`, docs/CATEGORISER.md): the
/// weights file rayo runs, the features the model reads, and how to
/// fine-tune it.
class ModelManifest {
  const ModelManifest({
    required this.weightsFile,
    required this.weightsSha256,
    required this.weightsSizeBytes,
    required this.weightsFormatVersion,
    required this.featureSchemaVersion,
    required this.featureConfig,
    required this.inputName,
    required this.inputDtype,
    required this.inputShape,
    required this.layout,
    required this.outputs,
    this.fineTune,
  });

  /// Reads a manifest. Throws [FormatException] when a field is missing or
  /// of the wrong type.
  factory ModelManifest.fromJson(Map<String, Object?> json) {
    final config = _field<Map<String, Object?>>(json, 'feature_config');
    final input = _field<Map<String, Object?>>(json, 'input');
    return ModelManifest(
      weightsFile: _field<String>(json, 'weights_file'),
      weightsSha256: _field<String>(json, 'weights_sha256').toLowerCase(),
      weightsSizeBytes: _field<int>(json, 'weights_size_bytes'),
      weightsFormatVersion: _field<int>(json, 'weights_format_version'),
      featureSchemaVersion: _field<int>(json, 'feature_schema_version'),
      featureConfig: FeatureConfig(
        maxTokens: _field<int>(config, 'max_tokens'),
        hashBuckets: _field<int>(config, 'hash_buckets'),
      ),
      inputName: _field<String>(input, 'name'),
      inputDtype: _field<String>(input, 'dtype'),
      inputShape: _list<int>(input, 'shape'),
      layout: _list<String>(json, 'layout'),
      outputs: _list<String>(json, 'outputs'),
      fineTune: switch (json['fine_tune']) {
        null => null,
        final Map<String, Object?> t => FineTuneManifest.fromJson(t),
        _ => throw const FormatException('manifest: bad fine_tune'),
      },
    );
  }

  /// The model's plain weights with rayo's graph (pesaclarity-ml
  /// docs/WEIGHTS.md), a file beside the manifest, with its SHA-256 and
  /// size. The manifest's `source` (the ONNX file they were quantised from)
  /// is provenance only; the app does not ship it.
  final String weightsFile;
  final String weightsSha256;
  final int weightsSizeBytes;
  final int weightsFormatVersion;
  final int featureSchemaVersion;
  final FeatureConfig featureConfig;
  final String inputName;
  final String inputDtype;
  final List<int> inputShape;
  final List<String> layout;

  /// The graph's outputs by name; the app reads `category`.
  final List<String> outputs;

  /// How the app may fine-tune the model, when the export says.
  final FineTuneManifest? fineTune;

  /// Why this app cannot feed or read the model; empty when it can.
  ///
  /// The model is refused when its weights format is not one this app
  /// reads, when its feature schema version is not the one in
  /// `features.dart`, or when its config, input, layout or outputs differ
  /// from what that pipeline produces and reads.
  List<String> incompatibilities() {
    final cfg = featureConfig;
    return [
      if (weightsFormatVersion != plainWeightsFormatVersion)
        'weights format $weightsFormatVersion; '
            'this app reads $plainWeightsFormatVersion',
      if (featureSchemaVersion != features.featureSchemaVersion)
        'feature schema version $featureSchemaVersion; '
            'this app implements ${features.featureSchemaVersion}',
      if (!cfg.isValid) 'feature config out of range: $cfg',
      if (inputName != 'features') 'input name $inputName',
      if (inputDtype != 'int32') 'input dtype $inputDtype',
      if (inputShape.length != 2 ||
          inputShape[0] != -1 ||
          inputShape[1] != cfg.width)
        'input shape $inputShape',
      if (!_sameList(layout, cfg.layout)) 'feature layout differs',
      if (!outputs.contains(categoryOutput)) 'no $categoryOutput output',
    ];
  }

  /// The output the app reads: the softmax, in `labels.json` order.
  static const categoryOutput = 'category';
}

/// The manifest's `fine_tune` block: which tensors the phone trains and
/// how, by pesaclarity-ml's docs/FINE-TUNING.md (`akili.export.fine_tune`).
class FineTuneManifest {
  const FineTuneManifest({
    required this.specVersion,
    required this.trains,
    required this.input,
    required this.weightShapes,
    required this.settings,
  });

  factory FineTuneManifest.fromJson(Map<String, Object?> json) {
    final shapes = _field<Map<String, Object?>>(json, 'weights');
    final tune = _field<Map<String, Object?>>(json, 'settings');
    T setting<T>(String key) => _field<T>(tune, key);
    return FineTuneManifest(
      specVersion: _field<int>(json, 'spec_version'),
      trains: _list<String>(json, 'trains'),
      input: _field<String>(json, 'input'),
      weightShapes: {
        for (final MapEntry(:key, :value) in shapes.entries)
          key: switch (value) {
            final List<Object?> dims
                when dims.isNotEmpty && dims.every((d) => d is int && d > 0) =>
              dims.cast<int>(),
            _ => throw FormatException('fine_tune: bad shape for $key'),
          },
      },
      settings: FineTuneSettings(
        learningRate: setting<num>('learning_rate').toDouble(),
        epochs: setting<int>('epochs'),
        batchSize: setting<int>('batch_size'),
        maxExamples: setting<int>('max_examples'),
        minExamples: setting<int>('min_examples'),
        minHoursBetweenRuns: setting<int>('min_hours_between_runs'),
      ),
    );
  }

  /// The version of FINE-TUNING.md's step this app implements.
  static const supportedSpecVersion = 1;

  /// The tensors the step trains, in rayo's `[out, in]` layout, in the
  /// order the spec lists them.
  static const tensorNames = [
    'hidden.kernel',
    'hidden.bias',
    'category.kernel',
    'category.bias',
  ];

  final int specVersion;
  final List<String> trains;

  /// The layer whose input the step starts from: `hidden`.
  final String input;

  /// Each trained tensor's shape, by name.
  final Map<String, List<int>> weightShapes;
  final FineTuneSettings settings;

  /// Why the app cannot fine-tune this model; empty when it can. The
  /// shapes are checked against the weights file when it is read.
  List<String> problems() => [
    if (specVersion != supportedSpecVersion)
      'fine-tuning spec $specVersion; this app implements '
          '$supportedSpecVersion',
    if (!_sameList(trains, tensorNames)) 'trains $trains',
    if (input != 'hidden') 'fine-tunes from $input',
    for (final name in tensorNames)
      if (!weightShapes.containsKey(name)) 'no shape for $name',
    if (!settings.isValid) 'fine-tune settings out of range',
  ];
}

/// How to fine-tune on the phone, from the manifest.
class FineTuneSettings {
  const FineTuneSettings({
    required this.learningRate,
    required this.epochs,
    required this.batchSize,
    required this.maxExamples,
    required this.minExamples,
    required this.minHoursBetweenRuns,
  });

  final double learningRate;
  final int epochs;
  final int batchSize;

  /// Most recent confirmations used per run.
  final int maxExamples;

  /// Fewer confirmations than this and the run waits.
  final int minExamples;

  /// Hours to wait after a run before the next one.
  final int minHoursBetweenRuns;

  bool get isValid =>
      learningRate > 0 &&
      learningRate.isFinite &&
      epochs >= 1 &&
      batchSize >= 1 &&
      minExamples >= 1 &&
      minExamples <= maxExamples &&
      minHoursBetweenRuns >= 1;
}

T _field<T>(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! T) throw FormatException('manifest: bad or missing $key');
  return value;
}

List<E> _list<E>(Map<String, Object?> map, String key) {
  final items = _field<List<Object?>>(map, key);
  if (items.any((e) => e is! E)) {
    throw FormatException('manifest: bad $key');
  }
  return items.cast<E>();
}

bool _sameList<E>(List<E> a, List<E> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// `labels.json`: the categoriser's output order, as category keys.
class ModelLabels {
  const ModelLabels({required this.version, required this.labels});

  factory ModelLabels.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    final labels = json['labels'];
    if (version is! int ||
        labels is! List ||
        labels.isEmpty ||
        labels.any((l) => l is! String)) {
      throw const FormatException('labels.json: bad version or labels');
    }
    final list = labels.cast<String>();
    if (list.toSet().length != list.length) {
      throw const FormatException('labels.json: duplicate labels');
    }
    return ModelLabels(version: version, labels: List.unmodifiable(list));
  }

  /// Version of the category set the model was trained on.
  final int version;

  /// Category keys in output-layer order.
  final List<String> labels;
}
