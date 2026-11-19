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
  const CategoryScore(this.key, this.confidence, {this.source});

  /// A seeded category key, such as `groceries`.
  final String key;
  final double confidence;

  /// Where this score came from, when it is not the categoriser's own
  /// [Categoriser.source] (a rule's answer under [RulesFirstCategoriser]).
  final SuggestionSource? source;

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

/// A loaded categoriser model, kept behind this interface so the domain does
/// not depend on a runtime: `categoriser.weights` on rayo, or the same
/// network in Dart, with weights fine-tuned on the phone or where rayo
/// cannot load (`DartCategoriserRuntime`).
abstract interface class CategoriserRuntime {
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
class ModelCategoriser implements Categoriser {
  ModelCategoriser._(this._runtime, this._config, this.labels);

  /// Wraps [runtime], refusing it with [ModelRefused] when the manifest
  /// asks for features this app cannot produce or the labels do not match
  /// the model's outputs. The runtime is closed when refused.
  factory ModelCategoriser({
    required ModelManifest manifest,
    required ModelLabels labels,
    required CategoriserRuntime runtime,
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
    return ModelCategoriser._(runtime, manifest.featureConfig, labels);
  }

  final CategoriserRuntime _runtime;
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

/// The model, except where the rules are certain: when [rules] give an
/// answer at [certainRuleConfidence] or more (the message type settles it,
/// such as airtime, a Fuliza repayment or charges, or the payee is a
/// well-known one in the rules' table, such as Naivas or KPLC), that answer
/// is used and [model] is not run. Every other transaction, a guess from a
/// word in the payee's name included, goes to [model].
///
/// The person's own choices for a payee and the payee's default category
/// come before both, in `CategorySuggester` and `applyPayee`.
class RulesFirstCategoriser implements Categoriser {
  const RulesFirstCategoriser({required this.rules, required this.model});

  final Categoriser rules;
  final Categoriser model;

  @override
  SuggestionSource get source => model.source;

  @override
  List<CategoryScore> score(CategoriserInput input) {
    final ruled = rules.score(input);
    if (ruled.isNotEmpty && ruled.first.confidence >= certainRuleConfidence) {
      return [
        for (final s in ruled)
          CategoryScore(s.key, s.confidence, source: s.source ?? rules.source),
      ];
    }
    return model.score(input);
  }

  @override
  void close() {
    rules.close();
    model.close();
  }
}

/// A rule answer at or above this confidence is used instead of the model:
/// the confidence the rules give when the message type settles the category
/// (`kindRuleConfidence`) or the payee is a well-known one
/// (`knownPayeeRuleConfidence`). Weaker rule guesses, such as a word in the
/// payee's name (`payeeRuleConfidence`), leave the transaction to the model.
const certainRuleConfidence = 0.9;
