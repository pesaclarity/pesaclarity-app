import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'categoriser.dart';
import 'learning.dart';
import 'model_manifest.dart';

/// A model that can be fine-tuned: the four signatures of
/// `categoriser-train.tflite`. [run] is the `infer` signature, so a tuned
/// runtime can stand in for the plain one.
abstract interface class TrainableRuntime implements TfliteRuntime {
  /// One SGD step on [rows] with label indices [labels]; returns the loss.
  double train(List<List<int>> rows, List<int> labels, double learningRate);

  /// The current weights, by name.
  Map<String, Float32List> save();

  /// Loads weights saved earlier.
  void restore(Map<String, Float32List> weights);
}

/// Opens a trainable model from its bytes, for rows [width] long.
typedef TrainableRuntimeOpener = TrainableRuntime Function(
  Uint8List modelBytes,
  int width,
);

/// The trainable model as installed and checked against its manifest.
class TrainableModel {
  const TrainableModel({
    required this.manifest,
    required this.bytes,
    required this.labels,
    required this.width,
    required this.featureSchemaVersion,
  });

  final TrainableManifest manifest;
  final Uint8List bytes;

  /// Category keys in output order.
  final List<String> labels;
  final int width;
  final int featureSchemaVersion;
}

/// Weights fine-tuned on this phone for one trainable model, kept in the
/// encrypted database of the space they were learned in.
class TunedWeights {
  const TunedWeights({
    required this.trainableSha256,
    required this.trainedAt,
    required this.exampleCount,
    required this.weights,
  });

  /// Reads a saved record; null when it is malformed.
  static TunedWeights? fromJson(Map<String, Object?> json) {
    final sha = json['trainable_sha256'];
    final at = json['trained_at_ms'];
    final count = json['examples'];
    final raw = json['weights'];
    if (sha is! String || at is! int || count is! int || raw is! Map) {
      return null;
    }
    final weights = <String, Float32List>{};
    for (final MapEntry(:key, :value) in raw.entries) {
      if (key is! String || value is! String) return null;
      final Uint8List bytes;
      try {
        bytes = base64Decode(value);
      } on FormatException {
        return null;
      }
      if (bytes.length % 4 != 0) return null;
      final data = ByteData.sublistView(bytes);
      weights[key] = Float32List.fromList([
        for (var i = 0; i < bytes.length; i += 4)
          data.getFloat32(i, Endian.little),
      ]);
    }
    return TunedWeights(
      trainableSha256: sha,
      trainedAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      exampleCount: count,
      weights: weights,
    );
  }

  final String trainableSha256;
  final DateTime trainedAt;
  final int exampleCount;
  final Map<String, Float32List> weights;

  Map<String, Object?> toJson() => {
    'trainable_sha256': trainableSha256,
    'trained_at_ms': trainedAt.millisecondsSinceEpoch,
    'examples': exampleCount,
    'weights': {
      for (final MapEntry(:key, :value) in weights.entries)
        key: base64Encode(_littleEndian(value)),
    },
  };

  /// Whether these weights were learned on [manifest]'s model and have the
  /// shapes it expects.
  bool fits(TrainableManifest manifest) {
    if (trainableSha256 != manifest.sha256) return false;
    for (final name in TrainableManifest.weightNames) {
      final shape = manifest.weightShapes[name];
      final w = weights[name];
      if (shape == null || w == null) return false;
      if (w.length != shape.fold(1, (a, b) => a * b)) return false;
      if (w.any((v) => !v.isFinite)) return false;
    }
    return true;
  }
}

Uint8List _littleEndian(Float32List values) {
  final out = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    out.setFloat32(i * 4, values[i], Endian.little);
  }
  return out.buffer.asUint8List();
}

/// Where tuned weights and the time of the last learning run are kept.
abstract interface class TunedWeightsStore {
  Future<TunedWeights?> read();

  Future<void> write(TunedWeights weights);

  Future<DateTime?> lastRun();

  Future<void> markRun(DateTime at);
}

/// Fine-tunes [model] on the person's latest confirmations, on the phone.
///
/// Each run starts from the installed model, not from the last tuned
/// weights, so a run never builds on an earlier mistake. Settings come from
/// the manifest. Nothing leaves the phone.
class ModelFineTuner implements OnDeviceTrainer {
  ModelFineTuner({
    required this.model,
    required this.open,
    required this.store,
    required this.now,
    Random? random,
  }) : _random = random ?? Random();

  final TrainableModel model;
  final TrainableRuntimeOpener open;
  final TunedWeightsStore store;
  final DateTime Function() now;
  final Random _random;

  @override
  Future<bool> fineTune(List<TrainingExample> examples) async {
    final tune = model.manifest.fineTune;
    final index = {
      for (var i = 0; i < model.labels.length; i++) model.labels[i]: i,
    };
    final usable = [
      for (final e in examples)
        if (e.featureSchemaVersion == model.featureSchemaVersion &&
            e.features.length == model.width &&
            index.containsKey(e.label))
          e,
    ];
    // Examples arrive oldest first; keep the most recent.
    final recent = usable.length > tune.maxExamples
        ? usable.sublist(usable.length - tune.maxExamples)
        : usable;
    if (recent.length < tune.minExamples) return false;

    final runtime = open(model.bytes, model.width);
    try {
      final order = List.generate(recent.length, (i) => i);
      for (var epoch = 0; epoch < tune.epochs; epoch++) {
        order.shuffle(_random);
        for (var start = 0; start < order.length; start += tune.batchSize) {
          final batch = order.sublist(
            start,
            min(start + tune.batchSize, order.length),
          );
          final loss = runtime.train(
            [for (final i in batch) recent[i].features],
            [for (final i in batch) index[recent[i].label]!],
            tune.learningRate,
          );
          if (!loss.isFinite) return false;
        }
      }
      final tuned = TunedWeights(
        trainableSha256: model.manifest.sha256,
        trainedAt: now().toUtc(),
        exampleCount: recent.length,
        weights: runtime.save(),
      );
      if (!tuned.fits(model.manifest)) return false;
      await store.write(tuned);
      return true;
    } finally {
      runtime.close();
    }
  }
}

/// Runs [learning] at most once per [interval], only while [isCharging]
/// says so and only with the person's consent.
class LearningSchedule {
  LearningSchedule({
    required this.learning,
    required this.optedIn,
    required this.isCharging,
    required this.store,
    required this.interval,
    required this.now,
  });

  final CategoriserLearning learning;
  final bool Function() optedIn;
  final Future<bool> Function() isCharging;
  final TunedWeightsStore store;
  final Duration interval;
  final DateTime Function() now;

  /// The outcome when a run happened, else null.
  Future<LearningOutcome?> maybeRun() async {
    if (!optedIn()) return null;
    final last = await store.lastRun();
    if (last != null && now().difference(last) < interval) return null;
    if (!await isCharging()) return null;
    final outcome = await learning.run();
    if (outcome == LearningOutcome.fineTuned ||
        outcome == LearningOutcome.noExamples ||
        outcome == LearningOutcome.uploaded) {
      await store.markRun(now());
    }
    return outcome;
  }
}
