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
