import '../enums.dart';
import 'features.dart';
import 'model_manifest.dart';

/// What a categoriser reads about one transaction.
class CategoriserInput {
  const CategoriserInput({
    required this.payee,
    required this.amountMinor,
    required this.isInflow,
    required this.occurredAt,
    this.kind,
  });

  /// Counterparty text as the message printed it, or the payee's name.
  final String payee;
  final int amountMinor;
  final bool isInflow;
  final DateTime occurredAt;

  /// The parser's message type, for rules. The model does not read it.
  final TransactionKind? kind;

  FeatureInput get features => FeatureInput(
    payee: payee,
    amountMinor: amountMinor,
    isInflow: isInflow,
    timestampMs: occurredAt.millisecondsSinceEpoch,
  );
}

/// A category key with a confidence from 0 to 1.
class CategoryScore {
  const CategoryScore(this.key, this.confidence);

  /// A seeded category key, such as `groceries`.
  final String key;
  final double confidence;

  @override
  String toString() => 'CategoryScore($key, $confidence)';
}

/// Suggests categories for transactions.
abstract interface class Categoriser {
  SuggestionSource get source;

  /// Category keys with confidence, best first. Empty when it has no view.
  List<CategoryScore> score(CategoriserInput input);

  /// Frees native resources, if any.
  void close();
}

/// A loaded TFLite interpreter, kept behind this interface so the domain
/// does not depend on a particular plugin.
abstract interface class TfliteRuntime {
  /// Number of output classes for one row.
  int get outputSize;

  /// Runs one int32 row and returns the softmax.
  List<double> run(List<int> row);

  void close();
}

/// Thrown when an installed model cannot be used.
class ModelRefused implements Exception {
  const ModelRefused(this.reasons);

  final List<String> reasons;

  @override
  String toString() => 'ModelRefused: ${reasons.join('; ')}';
}

/// The exported categoriser from pesaclarity-ml, run on the phone.
class TfliteCategoriser implements Categoriser {
  TfliteCategoriser._(this._runtime, this._config, this.labels);

  /// Wraps [runtime], refusing it with [ModelRefused] when the manifest
  /// asks for features this app cannot produce or the labels do not match
  /// the model's outputs. The runtime is closed when refused.
  factory TfliteCategoriser({
    required ModelManifest manifest,
    required ModelLabels labels,
    required TfliteRuntime runtime,
  }) {
    final reasons = [
      ...manifest.incompatibilities(),
      if (labels.labels.length != runtime.outputSize)
        '${labels.labels.length} labels for ${runtime.outputSize} outputs',
    ];
    if (reasons.isNotEmpty) {
      runtime.close();
      throw ModelRefused(reasons);
    }
    return TfliteCategoriser._(runtime, manifest.featureConfig, labels);
  }

  final TfliteRuntime _runtime;
  final FeatureConfig _config;
  final ModelLabels labels;

  @override
  SuggestionSource get source => SuggestionSource.model;

  @override
  List<CategoryScore> score(CategoriserInput input) {
    final probs = _runtime.run(encodeFeatures(input.features, _config));
    return [
      for (var i = 0; i < labels.labels.length; i++)
        CategoryScore(labels.labels[i], probs[i]),
    ]..sort((a, b) => b.confidence.compareTo(a.confidence));
  }

  @override
  void close() => _runtime.close();
}
