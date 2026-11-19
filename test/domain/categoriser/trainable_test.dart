import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/categoriser/features.dart';
import 'package:pesaclarity/src/domain/categoriser/learning.dart';
import 'package:pesaclarity/src/domain/categoriser/model_manifest.dart';
import 'package:pesaclarity/src/domain/categoriser/trainable.dart';

import '../ml/plain_weights_writer.dart';
import 'categoriser_test.dart' show manifestJson;

const width = 13;
const _config = FeatureConfig(hashBuckets: 16);

/// The manifest's `fine_tune` block for [tinyWeights].
Map<String, Object?> fineTuneJson({
  int specVersion = 1,
  Map<String, Object?>? settings,
  Map<String, Object?>? weights,
}) => {
  'spec_version': specVersion,
  'trains': FineTuneManifest.tensorNames,
  'input': 'hidden',
  'weights':
      weights ??
      {
        'hidden.kernel': [3, 6],
        'hidden.bias': [3],
        'category.kernel': [2, 3],
        'category.bias': [2],
      },
  'settings':
      settings ??
      {
        'learning_rate': 0.05,
        'epochs': 3,
        'batch_size': 4,
        'max_examples': 10,
        'min_examples': 5,
        'min_hours_between_runs': 24,
      },
};

/// A categoriser's weights file small enough to read: 16 token rows of
/// width 1 (int8, one scale), five context tables of width 1, a hidden
/// layer of 3 (int8, a scale per output) and 2 classes.
Uint8List tinyWeights({String model = 'categoriser'}) => writePlainWeights(
  model: model,
  tensors: [
    PlainTensorSpec.int8(
      'token_embedding.table',
      [16, 1],
      List.generate(16, (i) => i * 8 - 64),
      scales: [0.01],
    ),
    for (final (i, rows) in [12, 2, 6, 7, 3].indexed)
      PlainTensorSpec.float32('context_$i.table', [
        rows,
        1,
      ], List.generate(rows, (r) => (r - i) / 10)),
    PlainTensorSpec.int8(
      'hidden.kernel',
      [3, 6],
      List.generate(18, (i) => (i * 37 % 255) - 127),
      scales: [0.01, 0.02, 0.005],
      axis: 0,
    ),
    PlainTensorSpec.float32('hidden.bias', [3], [0.1, -0.1, 0.05]),
    PlainTensorSpec.float32(
      'category.kernel',
      [2, 3],
      [0.5, -0.5, 0.25, -0.25, 0.5, 0.1],
    ),
    PlainTensorSpec.float32('category.bias', [2], [0, 0.1]),
  ],
);

CategoriserNetwork tinyNetwork() =>
    CategoriserNetwork.parse(tinyWeights(), _config);

class MemoryStore implements TunedWeightsStore {
  TunedWeights? weights;
  DateTime? last;
  var writes = 0;

  @override
  Future<TunedWeights?> read() async => weights;

  @override
  Future<void> write(TunedWeights w) async {
    writes++;
    weights = w;
  }

  @override
  Future<DateTime?> lastRun() async => last;

  @override
  Future<void> markRun(DateTime at) async => last = at;
}

FineTunableModel model({Map<String, Object?>? fineTune, String sha = 'cd'}) =>
    FineTunableModel(
      manifest: FineTuneManifest.fromJson(fineTune ?? fineTuneJson()),
      weightsSha256: sha,
      network: tinyNetwork(),
      labels: const ['groceries', 'eating_out'],
      featureSchemaVersion: 1,
    );

TrainingExample example(int i, {String label = 'groceries', int schema = 1}) =>
    TrainingExample(
      features: [i % 16, 0, 0, 0, 0, 0, 0, 0, i % 12, i % 2, i % 6, i % 7, 0],
      label: label,
      featureSchemaVersion: schema,
    );

void main() {
  final now = DateTime.utc(2026, 11, 4, 9);

  group('manifest', () {
    test('reads the fine_tune block', () {
      final m = ModelManifest.fromJson({
        ...manifestJson(),
        'fine_tune': fineTuneJson(),
      });
      final t = m.fineTune!;
      expect(t.problems(), isEmpty);
      expect(t.weightShapes['hidden.kernel'], [3, 6]);
      expect(t.settings.learningRate, 0.05);
      expect(t.settings.minHoursBetweenRuns, 24);
    });

    test('a model without one has none', () {
      expect(ModelManifest.fromJson(manifestJson()).fineTune, isNull);
    });

    test('a malformed block is refused', () {
      expect(
        () => ModelManifest.fromJson({...manifestJson(), 'fine_tune': 'x'}),
        throwsFormatException,
      );
      expect(
        () => FineTuneManifest.fromJson(
          fineTuneJson(
            weights: {
              'hidden.kernel': [0, 2],
            },
          ),
        ),
        throwsFormatException,
      );
    });

    test('lists what stops fine-tuning', () {
      final t = FineTuneManifest.fromJson({
        ...fineTuneJson(
          specVersion: 2,
          weights: {
            'hidden.kernel': [3, 6],
          },
          settings: {
            'learning_rate': 0.05,
            'epochs': 1,
            'batch_size': 1,
            'max_examples': 2,
            'min_examples': 5,
            'min_hours_between_runs': 24,
          },
        ),
        'input': 'category',
      });
      expect(t.problems(), [
        'fine-tuning spec 2; this app implements 1',
        'fine-tunes from category',
        'no shape for hidden.bias',
        'no shape for category.kernel',
        'no shape for category.bias',
        'fine-tune settings out of range',
      ]);
    });
  });

  group('CategoriserNetwork', () {
    test('reads the tensors in rayo\'s layout, the kernel dequantised', () {
      final n = tinyNetwork();
      expect(n.width, width);
      expect(n.shipped.shapes, {
        'hidden.kernel': [3, 6],
        'hidden.bias': [3],
        'category.kernel': [2, 3],
        'category.bias': [2],
      });
      // Row 1 of the kernel has scale 0.02.
      expect(
        n.shipped.hiddenKernel[6],
        closeTo(((6 * 37 % 255) - 127) * 0.02, 1e-6),
      );
    });

    test('f is the mean of the tokens that are not 0, then the contexts', () {
      final n = tinyNetwork();
      final f = n.input([3, 0, 5, 0, 0, 0, 0, 0, 2, 1, 0, 6, 2]);
      // Token rows 3 and 5: (3 * 8 - 64) and (5 * 8 - 64), times 0.01.
      expect(f[0], closeTo(((-40 + -24) / 2) * 0.01, 1e-7));
      expect(f.sublist(1), [
        for (final v in [0.2, 0.0, -0.2, 0.3, -0.2]) closeTo(v, 1e-7),
      ]);
      // No tokens: the sum over none, divided by 1.
      expect(n.input([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])[0], 0);
    });

    test('refuses ids outside its tables and rows of another width', () {
      final n = tinyNetwork();
      expect(
        () => n.input([16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        throwsArgumentError,
      );
      expect(
        () => n.input([1, 0, 0, 0, 0, 0, 0, 0, 12, 0, 0, 0, 0]),
        throwsArgumentError,
      );
      expect(() => n.input([1, 2]), throwsArgumentError);
    });

    test('refuses another model\'s weights or a table of another size', () {
      expect(
        () => CategoriserNetwork.parse(tinyWeights(model: 'reader'), _config),
        throwsFormatException,
      );
      expect(
        () => CategoriserNetwork.parse(tinyWeights(), const FeatureConfig()),
        throwsFormatException,
      );
    });

    test('the Dart runtime gives a softmax per row', () {
      final runtime = DartCategoriserRuntime(tinyNetwork());
      expect(runtime.outputSize, 2);
      final p = runtime.run(example(3).features);
      expect(p[0] + p[1], closeTo(1, 1e-12));
    });
  });

  group('TunedWeights', () {
    TunedWeights tuned({String sha = 'cd', Map<String, Float32List>? w}) =>
        TunedWeights(
          weightsSha256: sha,
          trainedAt: now,
          exampleCount: 7,
          weights: w ?? tinyNetwork().shipped.toNamed(),
        );

    test('round-trips through JSON, by tensor name', () {
      final json = tuned().toJson();
      expect((json['weights']! as Map).keys, FineTuneManifest.tensorNames);
      final back = TunedWeights.fromJson(json)!;
      expect(back.weightsSha256, 'cd');
      expect(back.specVersion, 1);
      expect(back.trainedAt, now);
      expect(back.exampleCount, 7);
      expect(back.weights['hidden.kernel'], tuned().weights['hidden.kernel']);
      expect(back.fits(model()), isTrue);
    });

    test('only fits the weights file it was learned on, with its shapes', () {
      final m = model();
      expect(tuned(sha: 'ef').fits(m), isFalse);
      final short = {...tuned().weights, 'category.kernel': Float32List(3)};
      expect(tuned(w: short).fits(m), isFalse);
      final nan = {
        ...tuned().weights,
        'category.bias': Float32List.fromList([double.nan, 0]),
      };
      expect(tuned(w: nan).fits(m), isFalse);
      final other = TunedWeights.fromJson({
        ...tuned().toJson(),
        'spec_version': 2,
      })!;
      expect(other.fits(m), isFalse);
    });

    test('a malformed or TFLite-era record reads as none', () {
      expect(TunedWeights.fromJson({'weights_sha256': 'cd'}), isNull);
      expect(
        TunedWeights.fromJson({
          ...tuned().toJson(),
          'weights': {'hidden.kernel': 'not base64!'},
        }),
        isNull,
      );
      // What the app saved for categoriser-train.tflite.
      expect(
        TunedWeights.fromJson({
          'trainable_sha256': 'cd',
          'trained_at_ms': 0,
          'examples': 7,
          'weights': {'w1': 'AAAAAA=='},
        }),
        isNull,
      );
    });
  });

  group('ModelFineTuner', () {
    late MemoryStore store;

    ModelFineTuner tuner([FineTunableModel? m]) => ModelFineTuner(
      model: m ?? model(),
      store: store,
      now: () => now,
      random: Random(1),
    );

    setUp(() => store = MemoryStore());

    test('waits for enough usable confirmations', () async {
      final examples = [
        for (var i = 0; i < 4; i++) example(i),
        example(9, label: 'not_in_model'),
        example(9, schema: 2),
        const TrainingExample(
          features: [1],
          label: 'groceries',
          featureSchemaVersion: 1,
        ),
        // A token id outside the model's 16 rows.
        TrainingExample(
          features: [99, ...List.filled(12, 0)],
          label: 'groceries',
          featureSchemaVersion: 1,
        ),
      ];
      expect(await tuner().fineTune(examples), isFalse);
      expect(store.writes, 0);
    });

    test('trains on the latest examples with the manifest settings', () async {
      final examples = [
        for (var i = 0; i < 12; i++)
          example(i, label: i.isEven ? 'groceries' : 'eating_out'),
      ];
      final m = model();
      final shipped = m.network.shipped.copy();
      expect(await tuner(m).fineTune(examples), isTrue);

      final saved = store.weights!;
      expect(saved.weightsSha256, 'cd');
      expect(saved.exampleCount, 10);
      expect(saved.trainedAt, now);
      expect(saved.fits(m), isTrue);
      expect(saved.weights['category.bias'], isNot(shipped.categoryBias));

      // The same run by hand: 10 most recent, 3 epochs of batches of 4, in
      // the order the same Random gives, from the shipped weights.
      final recent = examples.sublist(2);
      final w = shipped.copy();
      final order = List.generate(10, (i) => i);
      final random = Random(1);
      for (var epoch = 0; epoch < 3; epoch++) {
        order.shuffle(random);
        for (var start = 0; start < 10; start += 4) {
          final batch = order.sublist(start, min(start + 4, 10));
          w.step(
            [for (final i in batch) m.network.input(recent[i].features)],
            [for (final i in batch) recent[i].label == 'groceries' ? 0 : 1],
            0.05,
          );
        }
      }
      for (final MapEntry(:key, :value) in w.toNamed().entries) {
        expect(saved.weights[key], value, reason: key);
      }
      // Each run starts from the shipped weights.
      expect(m.network.shipped.toNamed(), shipped.toNamed());
    });

    test('keeps nothing when training diverges', () async {
      final examples = [for (var i = 0; i < 6; i++) example(i)];
      final m = model(
        fineTune: fineTuneJson(
          settings: {
            'learning_rate': 1e300,
            'epochs': 3,
            'batch_size': 2,
            'max_examples': 10,
            'min_examples': 5,
            'min_hours_between_runs': 24,
          },
        ),
      );
      expect(await tuner(m).fineTune(examples), isFalse);
      expect(store.writes, 0);
    });
  });

  group('LearningSchedule', () {
    late MemoryStore store;
    late bool optedIn;
    late bool charging;
    late int chargingChecks;
    late List<TrainingExample> examples;
    late _Trainer trainer;
    late DateTime clock;

    LearningSchedule schedule({OnDeviceTrainer? t}) => LearningSchedule(
      learning: CategoriserLearning(
        optedIn: () => optedIn,
        examples: () async => examples,
        trainer: t ?? trainer,
      ),
      optedIn: () => optedIn,
      isCharging: () async {
        chargingChecks++;
        return charging;
      },
      store: store,
      interval: const Duration(hours: 24),
      now: () => clock,
    );

    setUp(() {
      store = MemoryStore();
      optedIn = true;
      charging = true;
      chargingChecks = 0;
      examples = [example(1)];
      trainer = _Trainer();
      clock = now;
    });

    test('does nothing without consent', () async {
      optedIn = false;
      expect(await schedule().maybeRun(), isNull);
      expect(chargingChecks, 0);
      expect(trainer.runs, 0);
    });

    test('waits while on battery', () async {
      charging = false;
      expect(await schedule().maybeRun(), isNull);
      expect(trainer.runs, 0);
      expect(store.last, isNull);
    });

    test('runs at most once per interval', () async {
      expect(await schedule().maybeRun(), LearningOutcome.fineTuned);
      expect(store.last, now);
      clock = now.add(const Duration(hours: 23));
      expect(await schedule().maybeRun(), isNull);
      expect(chargingChecks, 1);
      clock = now.add(const Duration(hours: 24));
      expect(await schedule().maybeRun(), LearningOutcome.fineTuned);
      expect(trainer.runs, 2);
    });

    test('too few confirmations still counts as a run', () async {
      trainer.result = false;
      expect(await schedule().maybeRun(), LearningOutcome.noExamples);
      expect(store.last, now);
    });

    test('a build without a trainer does not count as a run', () async {
      final none = LearningSchedule(
        learning: CategoriserLearning(
          optedIn: () => true,
          examples: () async => examples,
        ),
        optedIn: () => true,
        isCharging: () async => true,
        store: store,
        interval: const Duration(hours: 24),
        now: () => clock,
      );
      expect(await none.maybeRun(), LearningOutcome.unavailable);
      expect(store.last, isNull);
    });
  });
}

class _Trainer implements OnDeviceTrainer {
  var runs = 0;
  var result = true;

  @override
  Future<bool> fineTune(List<TrainingExample> examples) async {
    runs++;
    return result;
  }
}
