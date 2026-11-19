import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../ml/plain_weights.dart';
import 'categoriser.dart';
import 'features.dart';
import 'learning.dart';
import 'model_manifest.dart';

/// The categoriser's network read in Dart from `categoriser.weights`
/// (pesaclarity-ml docs/CATEGORISER.md), for learning on the phone and for
/// running the weights it learns.
///
/// [input] computes `f`, what the `hidden` layer reads, as rayo runs the
/// file's graph: the mean of the token embeddings over the tokens that are
/// not 0, then the five context embeddings, in float32. [shipped] holds the
/// four tensors that fine-tuning changes, as the file has them (an int8
/// kernel dequantised), in rayo's `[out, in]` layout.
class CategoriserNetwork {
  CategoriserNetwork._(
    this._tokenInt8,
    this._tokenFloat,
    this._tokenScale,
    this._contexts,
    this._contextRows, {
    required this.maxTokens,
    required this.tokenDim,
    required this.hashBuckets,
    required this.contextDim,
    required this.shipped,
  });

  /// Reads the network from [bytes] for rows of [config]. Throws
  /// [FormatException] when the file is not the categoriser's or its
  /// tensors do not fit together.
  factory CategoriserNetwork.parse(Uint8List bytes, FeatureConfig config) {
    final w = PlainWeights.parse(bytes);
    if (w.model != 'categoriser') {
      throw FormatException('weights of ${w.model}, not the categoriser');
    }
    List<int> dims(PlainTensor t, int rank, String name) {
      if (t.shape.length != rank || t.shape.any((d) => d <= 0)) {
        throw FormatException('$name: shape ${t.shape}');
      }
      return t.shape;
    }

    final table = w['token_embedding.table'];
    final [buckets, tokenDim] = dims(table, 2, 'token_embedding.table');
    if (buckets != config.hashBuckets) {
      throw FormatException('$buckets token rows for ${config.hashBuckets}');
    }
    if (table.int8 != null && table.axis != null) {
      throw const FormatException('token_embedding.table: one scale per row');
    }

    final contexts = <Float32List>[];
    final rows = <int>[];
    int? contextDim;
    for (var i = 0; i < contextColumns; i++) {
      final name = 'context_$i.table';
      final t = w[name];
      final [n, d] = dims(t, 2, name);
      if (contextDim != null && d != contextDim) {
        throw FormatException('$name: width $d');
      }
      contextDim = d;
      contexts.add(_real(t, name));
      rows.add(n);
    }

    final inputs = tokenDim + contextColumns * contextDim!;
    final [hidden, kernelIn] = dims(w['hidden.kernel'], 2, 'hidden.kernel');
    final [classes, categoryIn] = dims(
      w['category.kernel'],
      2,
      'category.kernel',
    );
    if (kernelIn != inputs || categoryIn != hidden) {
      throw const FormatException('dense layers do not fit the embeddings');
    }
    Float32List bias(String name, int n) {
      final t = w[name];
      if (dims(t, 1, name)[0] != n) throw FormatException('$name: ${t.shape}');
      return _real(t, name);
    }

    return CategoriserNetwork._(
      table.int8,
      table.float32,
      table.scales?[0] ?? 1,
      contexts,
      rows,
      maxTokens: config.maxTokens,
      tokenDim: tokenDim,
      hashBuckets: buckets,
      contextDim: contextDim,
      shipped: DenseWeights(
        inputs: inputs,
        hidden: hidden,
        classes: classes,
        hiddenKernel: _real(w['hidden.kernel'], 'hidden.kernel'),
        hiddenBias: bias('hidden.bias', hidden),
        categoryKernel: _real(w['category.kernel'], 'category.kernel'),
        categoryBias: bias('category.bias', classes),
      ),
    );
  }

  /// The context columns after the tokens: amount bucket, direction, hour
  /// bucket, weekday and month phase.
  static const contextColumns = 5;

  final int maxTokens;
  final Int8List? _tokenInt8;
  final Float32List? _tokenFloat;
  final double _tokenScale;
  final int tokenDim;
  final int hashBuckets;
  final List<Float32List> _contexts;
  final List<int> _contextRows;
  final int contextDim;

  /// The trained tensors as shipped; fine-tuning starts from a copy.
  final DenseWeights shipped;

  /// Length of the rows [input] takes.
  int get width => maxTokens + contextColumns;

  /// `f` for one encoded row: the masked mean of its token embeddings, then
  /// its five context embeddings, each step rounded to float32 as rayo
  /// runs the graph. Throws [ArgumentError] for a row of another length or
  /// an id outside its table.
  Float32List input(List<int> row) {
    if (row.length != width) {
      throw ArgumentError.value(row.length, 'row', 'expected $width');
    }
    final f = Float32List(shipped.inputs);
    var count = 0;
    final q = _tokenInt8;
    for (var t = 0; t < maxTokens; t++) {
      final id = row[t];
      if (id <= 0) continue;
      if (id >= hashBuckets) throw ArgumentError.value(id, 'token id');
      count++;
      final at = id * tokenDim;
      for (var j = 0; j < tokenDim; j++) {
        // Stored in a Float32List, each product and sum rounds to float32.
        f[j] += q == null
            ? _tokenFloat![at + j]
            : _f32(q[at + j] * _tokenScale);
      }
    }
    final divisor = max(count, 1);
    for (var j = 0; j < tokenDim; j++) {
      f[j] = f[j] / divisor;
    }
    for (var c = 0; c < contextColumns; c++) {
      final index = row[maxTokens + c];
      if (index < 0 || index >= _contextRows[c]) {
        throw ArgumentError.value(index, 'context $c');
      }
      final from = index * contextDim;
      f.setRange(
        tokenDim + c * contextDim,
        tokenDim + (c + 1) * contextDim,
        _contexts[c],
        from,
      );
    }
    return f;
  }
}

/// The four tensors fine-tuning changes (pesaclarity-ml docs/FINE-TUNING.md),
/// float32 in rayo's `[out, in]` layout: `hidden.kernel` `[hidden, inputs]`,
/// `hidden.bias`, `category.kernel` `[classes, hidden]` and `category.bias`.
class DenseWeights {
  DenseWeights({
    required this.inputs,
    required this.hidden,
    required this.classes,
    required this.hiddenKernel,
    required this.hiddenBias,
    required this.categoryKernel,
    required this.categoryBias,
  }) {
    if (hiddenKernel.length != hidden * inputs ||
        hiddenBias.length != hidden ||
        categoryKernel.length != classes * hidden ||
        categoryBias.length != classes) {
      throw ArgumentError('tensors of the wrong sizes');
    }
  }

  /// The tensors in [weights] by name, when they have [shapes]' sizes and
  /// finite values; else null.
  static DenseWeights? fromNamed(
    Map<String, Float32List> weights,
    Map<String, List<int>> shapes,
  ) {
    final kernel = shapes['hidden.kernel'];
    final category = shapes['category.kernel'];
    if (kernel == null || kernel.length != 2) return null;
    if (category == null || category.length != 2) return null;
    if (category[1] != kernel[0]) return null;
    final want = {
      'hidden.kernel': kernel[0] * kernel[1],
      'hidden.bias': kernel[0],
      'category.kernel': category[0] * category[1],
      'category.bias': category[0],
    };
    for (final MapEntry(:key, :value) in want.entries) {
      final w = weights[key];
      final shape = shapes[key];
      if (w == null || shape == null || w.length != value) return null;
      if (shape.fold(1, (a, b) => a * b) != value) return null;
      if (w.any((v) => !v.isFinite)) return null;
    }
    return DenseWeights(
      inputs: kernel[1],
      hidden: kernel[0],
      classes: category[0],
      hiddenKernel: Float32List.fromList(weights['hidden.kernel']!),
      hiddenBias: Float32List.fromList(weights['hidden.bias']!),
      categoryKernel: Float32List.fromList(weights['category.kernel']!),
      categoryBias: Float32List.fromList(weights['category.bias']!),
    );
  }

  final int inputs;
  final int hidden;
  final int classes;
  final Float32List hiddenKernel;
  final Float32List hiddenBias;
  final Float32List categoryKernel;
  final Float32List categoryBias;

  /// Each tensor's shape, as the manifest's `fine_tune.weights` gives them.
  Map<String, List<int>> get shapes => {
    'hidden.kernel': [hidden, inputs],
    'hidden.bias': [hidden],
    'category.kernel': [classes, hidden],
    'category.bias': [classes],
  };

  /// The tensors by name, as they are stored.
  Map<String, Float32List> toNamed() => {
    'hidden.kernel': hiddenKernel,
    'hidden.bias': hiddenBias,
    'category.kernel': categoryKernel,
    'category.bias': categoryBias,
  };

  DenseWeights copy() => DenseWeights(
    inputs: inputs,
    hidden: hidden,
    classes: classes,
    hiddenKernel: Float32List.fromList(hiddenKernel),
    hiddenBias: Float32List.fromList(hiddenBias),
    categoryKernel: Float32List.fromList(categoryKernel),
    categoryBias: Float32List.fromList(categoryBias),
  );

  /// `relu(f W1^T + b1)` and its pre-activation `z1`.
  (Float64List, Float64List) _hidden(Float32List f) {
    final z1 = Float64List(hidden);
    final h = Float64List(hidden);
    for (var o = 0; o < hidden; o++) {
      var sum = hiddenBias[o].toDouble();
      final row = o * inputs;
      for (var i = 0; i < inputs; i++) {
        sum += hiddenKernel[row + i] * f[i];
      }
      z1[o] = sum;
      h[o] = sum > 0 ? sum : 0;
    }
    return (z1, h);
  }

  /// `softmax(h W2^T + b2)`, less the row's largest score first.
  Float64List _softmax(Float64List h) {
    final p = Float64List(classes);
    var top = double.negativeInfinity;
    for (var k = 0; k < classes; k++) {
      var sum = categoryBias[k].toDouble();
      final row = k * hidden;
      for (var j = 0; j < hidden; j++) {
        sum += categoryKernel[row + j] * h[j];
      }
      p[k] = sum;
      if (sum > top) top = sum;
    }
    var total = 0.0;
    for (var k = 0; k < classes; k++) {
      p[k] = exp(p[k] - top);
      total += p[k];
    }
    for (var k = 0; k < classes; k++) {
      p[k] /= total;
    }
    return p;
  }

  /// The softmax for one row's `f`.
  List<double> probabilities(Float32List f) => _softmax(_hidden(f).$2);

  /// One SGD step of FINE-TUNING.md (spec version 1) on the rows [f] with
  /// label indices [labels], at [learningRate]: every gradient from the
  /// weights before the step, no dropout, momentum or weight decay. Returns
  /// the mean cross-entropy before the update.
  double step(List<Float32List> f, List<int> labels, double learningRate) {
    final n = f.length;
    if (n == 0 || labels.length != n) {
      throw ArgumentError('${labels.length} labels for $n rows');
    }
    final dW1 = Float64List(hidden * inputs);
    final db1 = Float64List(hidden);
    final dW2 = Float64List(classes * hidden);
    final db2 = Float64List(classes);
    var loss = 0.0;
    for (var r = 0; r < n; r++) {
      final y = labels[r];
      if (y < 0 || y >= classes) throw ArgumentError.value(y, 'label');
      final x = f[r];
      final (z1, h) = _hidden(x);
      final p = _softmax(h);
      loss -= log(p[y]);
      // g2 = (p - onehot(y)) / n
      final g2 = Float64List(classes);
      for (var k = 0; k < classes; k++) {
        g2[k] = (p[k] - (k == y ? 1 : 0)) / n;
        db2[k] += g2[k];
        final row = k * hidden;
        for (var j = 0; j < hidden; j++) {
          dW2[row + j] += g2[k] * h[j];
        }
      }
      // gh = (g2 W2) * (z1 > 0)
      for (var j = 0; j < hidden; j++) {
        if (z1[j] <= 0) continue;
        var gh = 0.0;
        for (var k = 0; k < classes; k++) {
          gh += g2[k] * categoryKernel[k * hidden + j];
        }
        db1[j] += gh;
        final row = j * inputs;
        for (var i = 0; i < inputs; i++) {
          dW1[row + i] += gh * x[i];
        }
      }
    }
    final lr = _f32(learningRate);
    void apply(Float32List w, Float64List g) {
      for (var i = 0; i < w.length; i++) {
        w[i] = w[i] - lr * g[i];
      }
    }

    apply(hiddenKernel, dW1);
    apply(hiddenBias, db1);
    apply(categoryKernel, dW2);
    apply(categoryBias, db2);
    return loss / n;
  }
}

/// The categoriser run in Dart: `f` from [network], then [weights], which
/// are tuned on this phone or the shipped ones. Suggestions use it with
/// tuned weights, and where rayo cannot load.
class DartCategoriserRuntime implements CategoriserRuntime {
  DartCategoriserRuntime(this.network, [DenseWeights? weights])
    : weights = weights ?? network.shipped {
    if (this.weights.inputs != network.shipped.inputs) {
      throw ArgumentError('weights for ${this.weights.inputs} inputs');
    }
  }

  final CategoriserNetwork network;
  final DenseWeights weights;

  @override
  int get outputSize => weights.classes;

  @override
  List<double> run(List<int> row) => weights.probabilities(network.input(row));

  @override
  void close() {}
}

/// The installed categoriser as fine-tuning needs it: its network, its
/// manifest's `fine_tune` block (checked against the network) and labels.
class FineTunableModel {
  const FineTunableModel({
    required this.manifest,
    required this.weightsSha256,
    required this.network,
    required this.labels,
    required this.featureSchemaVersion,
  });

  final FineTuneManifest manifest;

  /// The SHA-256 of `categoriser.weights`, which tuned weights are tied to.
  final String weightsSha256;
  final CategoriserNetwork network;

  /// Category keys in output order.
  final List<String> labels;
  final int featureSchemaVersion;

  int get width => network.width;
}

/// Weights fine-tuned on this phone for one `categoriser.weights`, kept in
/// the encrypted database of the space they were learned in: the four
/// tensors of FINE-TUNING.md by name, float32 in `[out, in]` layout.
class TunedWeights {
  const TunedWeights({
    required this.weightsSha256,
    required this.trainedAt,
    required this.exampleCount,
    required this.weights,
    this.specVersion = FineTuneManifest.supportedSpecVersion,
  });

  /// Reads a saved record; null when it is malformed, or was saved before
  /// the categoriser moved to rayo (keyed by `trainable_sha256`, with the
  /// TFLite model's `w1`..`b2`).
  static TunedWeights? fromJson(Map<String, Object?> json) {
    final sha = json['weights_sha256'];
    final spec = json['spec_version'];
    final at = json['trained_at_ms'];
    final count = json['examples'];
    final raw = json['weights'];
    if (sha is! String ||
        spec is! int ||
        at is! int ||
        count is! int ||
        raw is! Map) {
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
      weightsSha256: sha,
      specVersion: spec,
      trainedAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      exampleCount: count,
      weights: weights,
    );
  }

  final String weightsSha256;
  final int specVersion;
  final DateTime trainedAt;
  final int exampleCount;

  /// By tensor name: `hidden.kernel`, `hidden.bias`, `category.kernel` and
  /// `category.bias`.
  final Map<String, Float32List> weights;

  Map<String, Object?> toJson() => {
    'weights_sha256': weightsSha256,
    'spec_version': specVersion,
    'trained_at_ms': trainedAt.millisecondsSinceEpoch,
    'examples': exampleCount,
    'weights': {
      for (final MapEntry(:key, :value) in weights.entries)
        key: base64Encode(_littleEndian(value)),
    },
  };

  /// These weights as [model] runs them, when they were learned on its
  /// weights file by the step it implements and have the shapes its
  /// manifest gives; else null.
  DenseWeights? fitting(FineTunableModel model) {
    if (weightsSha256 != model.weightsSha256) return null;
    if (specVersion != model.manifest.specVersion) return null;
    return DenseWeights.fromNamed(weights, model.manifest.weightShapes);
  }

  bool fits(FineTunableModel model) => fitting(model) != null;
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

/// Fine-tunes [model] on the person's latest confirmations, on the phone,
/// with the step of pesaclarity-ml's docs/FINE-TUNING.md.
///
/// Each run starts from the installed weights, not from the last tuned
/// ones, so a run never builds on an earlier mistake. Settings come from
/// the manifest. Nothing leaves the phone.
class ModelFineTuner implements OnDeviceTrainer {
  ModelFineTuner({
    required this.model,
    required this.store,
    required this.now,
    Random? random,
  }) : _random = random ?? Random();

  final FineTunableModel model;
  final TunedWeightsStore store;
  final DateTime Function() now;
  final Random _random;

  @override
  Future<bool> fineTune(List<TrainingExample> examples) async {
    final tune = model.manifest.settings;
    final index = {
      for (var i = 0; i < model.labels.length; i++) model.labels[i]: i,
    };
    final usable = <(Float32List, int)>[];
    for (final e in examples) {
      final label = index[e.label];
      if (e.featureSchemaVersion != model.featureSchemaVersion ||
          e.features.length != model.width ||
          label == null) {
        continue;
      }
      try {
        usable.add((model.network.input(e.features), label));
      } on ArgumentError {
        // An id outside the model's tables: not one this model can read.
      }
    }
    // Examples arrive oldest first; keep the most recent.
    final recent = usable.length > tune.maxExamples
        ? usable.sublist(usable.length - tune.maxExamples)
        : usable;
    if (recent.length < tune.minExamples) return false;

    final weights = model.network.shipped.copy();
    final order = List.generate(recent.length, (i) => i);
    for (var epoch = 0; epoch < tune.epochs; epoch++) {
      order.shuffle(_random);
      for (var start = 0; start < order.length; start += tune.batchSize) {
        final batch = order.sublist(
          start,
          min(start + tune.batchSize, order.length),
        );
        final loss = weights.step(
          [for (final i in batch) recent[i].$1],
          [for (final i in batch) recent[i].$2],
          tune.learningRate,
        );
        if (!loss.isFinite) return false;
      }
    }
    final tuned = TunedWeights(
      weightsSha256: model.weightsSha256,
      trainedAt: now().toUtc(),
      exampleCount: recent.length,
      weights: weights.toNamed(),
    );
    if (!tuned.fits(model)) return false;
    await store.write(tuned);
    return true;
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

/// A tensor's real values as float32: a float32 tensor's own, an int8 one
/// times its scale, per output row when it has one per row.
Float32List _real(PlainTensor t, String name) {
  final q = t.int8;
  if (q == null) return t.float32!;
  final scales = t.scales!;
  switch (t.axis) {
    case null:
      return t.real();
    case 0:
      final rowLength = q.length ~/ t.shape[0];
      return Float32List.fromList([
        for (var i = 0; i < q.length; i++) q[i] * scales[i ~/ rowLength],
      ]);
    default:
      throw FormatException('$name: scales along axis ${t.axis}');
  }
}

final _scratch = Float32List(1);

/// [v] rounded to float32.
double _f32(double v) {
  _scratch[0] = v;
  return _scratch[0];
}
