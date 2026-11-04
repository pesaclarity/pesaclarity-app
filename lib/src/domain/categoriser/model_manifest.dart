import 'features.dart' as features;
import 'features.dart' show FeatureConfig;

/// `model-manifest.json`, written next to every exported categoriser by
/// pesaclarity-ml (`akili.export.manifest`).
class ModelManifest {
  const ModelManifest({
    required this.modelFile,
    required this.modelSha256,
    required this.modelSizeBytes,
    required this.featureSchemaVersion,
    required this.featureConfig,
    required this.inputName,
    required this.inputDtype,
    required this.inputShape,
    required this.layout,
    this.trainable,
  });

  /// Reads a manifest. Throws [FormatException] when a field is missing or
  /// of the wrong type.
  factory ModelManifest.fromJson(Map<String, Object?> json) {
    T field<T>(Map<String, Object?> map, String key) {
      final value = map[key];
      if (value is! T) throw FormatException('manifest: bad or missing $key');
      return value;
    }

    final config = field<Map<String, Object?>>(json, 'feature_config');
    final input = field<Map<String, Object?>>(json, 'input');
    List<E> list<E>(Map<String, Object?> map, String key) {
      final items = field<List<Object?>>(map, key);
      if (items.any((e) => e is! E)) {
        throw FormatException('manifest: bad $key');
      }
      return items.cast<E>();
    }

    return ModelManifest(
      modelFile: field<String>(json, 'model_file'),
      modelSha256: field<String>(json, 'model_sha256').toLowerCase(),
      modelSizeBytes: field<int>(json, 'model_size_bytes'),
      featureSchemaVersion: field<int>(json, 'feature_schema_version'),
      featureConfig: FeatureConfig(
        maxTokens: field<int>(config, 'max_tokens'),
        hashBuckets: field<int>(config, 'hash_buckets'),
      ),
      inputName: field<String>(input, 'name'),
      inputDtype: field<String>(input, 'dtype'),
      inputShape: list<int>(input, 'shape'),
      layout: list<String>(json, 'layout'),
      trainable: switch (json['trainable']) {
        null => null,
        final Map<String, Object?> t => TrainableManifest.fromJson(t),
        _ => throw const FormatException('manifest: bad trainable'),
      },
    );
  }

  final String modelFile;
  final String modelSha256;
  final int modelSizeBytes;
  final int featureSchemaVersion;
  final FeatureConfig featureConfig;
  final String inputName;
  final String inputDtype;
  final List<int> inputShape;
  final List<String> layout;

  /// The copy of the model that can be fine-tuned on the phone, when the
  /// export included one.
  final TrainableManifest? trainable;

  /// Why this app cannot feed the model; empty when it can.
  ///
  /// The model is refused when its feature schema version is not the one in
  /// `features.dart`, or when its config, input or layout differ from what
  /// that pipeline produces.
  List<String> incompatibilities() {
    final cfg = featureConfig;
    return [
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
    ];
  }
}

/// The `trainable` block of the manifest: `categoriser-train.tflite` and
/// how to fine-tune it (`akili.export.trainable` in pesaclarity-ml).
class TrainableManifest {
  const TrainableManifest({
    required this.file,
    required this.sha256,
    required this.sizeBytes,
    required this.signatures,
    required this.weightShapes,
    required this.fineTune,
  });

  factory TrainableManifest.fromJson(Map<String, Object?> json) {
    T field<T>(Map<String, Object?> map, String key) {
      final value = map[key];
      if (value is! T) throw FormatException('trainable: bad or missing $key');
      return value;
    }

    final shapes = field<Map<String, Object?>>(json, 'weights');
    final tune = field<Map<String, Object?>>(json, 'fine_tune');
    final signatures = field<List<Object?>>(json, 'signatures');
    if (signatures.any((s) => s is! String)) {
      throw const FormatException('trainable: bad signatures');
    }
    return TrainableManifest(
      file: field<String>(json, 'file'),
      sha256: field<String>(json, 'sha256').toLowerCase(),
      sizeBytes: field<int>(json, 'size_bytes'),
      signatures: signatures.cast<String>(),
      weightShapes: {
        for (final MapEntry(:key, :value) in shapes.entries)
          key: switch (value) {
            final List<Object?> dims
                when dims.every((d) => d is int && d > 0) =>
              dims.cast<int>(),
            _ => throw FormatException('trainable: bad shape for $key'),
          },
      },
      fineTune: FineTuneSettings(
        learningRate: field<num>(tune, 'learning_rate').toDouble(),
        epochs: field<int>(tune, 'epochs'),
        batchSize: field<int>(tune, 'batch_size'),
        maxExamples: field<int>(tune, 'max_examples'),
        minExamples: field<int>(tune, 'min_examples'),
        minHoursBetweenRuns: field<int>(tune, 'min_hours_between_runs'),
      ),
    );
  }

  /// Signatures the app calls.
  static const requiredSignatures = ['train', 'infer', 'save', 'restore'];

  /// Weights `save` returns and `restore` takes, in this order.
  static const weightNames = ['w1', 'b1', 'w2', 'b2'];

  final String file;
  final String sha256;
  final int sizeBytes;
  final List<String> signatures;
  final Map<String, List<int>> weightShapes;
  final FineTuneSettings fineTune;

  /// Why the app cannot fine-tune this model; empty when it can.
  List<String> problems() => [
    for (final s in requiredSignatures)
      if (!signatures.contains(s)) 'no $s signature',
    for (final w in weightNames)
      if (!weightShapes.containsKey(w)) 'no shape for $w',
    if (!fineTune.isValid) 'fine-tune settings out of range',
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

bool _sameList(List<String> a, List<String> b) {
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
