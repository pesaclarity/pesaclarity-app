import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/categoriser/learning.dart';
import 'package:pesaclarity/src/domain/categoriser/model_manifest.dart';
import 'package:pesaclarity/src/domain/categoriser/trainable.dart';

import 'categoriser_test.dart' show manifestJson;

const width = 13;
const shapes = {
  'w1': [3, 2],
  'b1': [2],
  'w2': [2, 2],
  'b2': [2],
};

Map<String, Object?> trainableJson({
  String sha = 'cd',
  Map<String, Object?>? fineTune,
  List<String> signatures = const ['train', 'infer', 'save', 'restore'],
}) => {
  'file': 'categoriser-train.tflite',
  'sha256': sha,
  'size_bytes': 64,
  'signatures': signatures,
  'weights': shapes,
  'fine_tune':
      fineTune ??
      {
        'learning_rate': 0.05,
        'epochs': 3,
        'batch_size': 4,
        'max_examples': 10,
        'min_examples': 5,
        'min_hours_between_runs': 24,
      },
};

class FakeTrainableRuntime implements TrainableRuntime {
  FakeTrainableRuntime({this.loss = 1.0, this.savedShapes = shapes});

  double loss;
  final Map<String, List<int>> savedShapes;
  final batches = <(List<List<int>>, List<int>, double)>[];
  Map<String, Float32List>? restored;
  var closed = false;
  var probs = [0.3, 0.7];

  @override
  int get outputSize => probs.length;

  @override
  List<double> run(List<int> row) => probs;

  @override
  double train(List<List<int>> rows, List<int> labels, double learningRate) {
    batches.add((rows, labels, learningRate));
    return loss;
  }

  @override
  Map<String, Float32List> save() => {
    for (final MapEntry(:key, :value) in savedShapes.entries)
      key: Float32List.fromList(
        List.generate(value.fold(1, (a, b) => a * b), (i) => i / 10),
      ),
  };

  @override
  void restore(Map<String, Float32List> weights) => restored = weights;

  @override
  void close() => closed = true;
}

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

TrainableModel model([Map<String, Object?>? json]) => TrainableModel(
  manifest: TrainableManifest.fromJson(json ?? trainableJson()),
  bytes: Uint8List(64),
  labels: const ['groceries', 'eating_out'],
  width: width,
  featureSchemaVersion: 1,
);

TrainingExample example(int i, {String label = 'groceries', int schema = 1}) =>
    TrainingExample(
      features: List.filled(width, i),
      label: label,
      featureSchemaVersion: schema,
    );

void main() {
  final now = DateTime.utc(2026, 11, 4, 9);

  group('manifest', () {
    test('reads the trainable block', () {
      final m = ModelManifest.fromJson({
        ...manifestJson(),
        'trainable': trainableJson(sha: 'CD'),
      });
      final t = m.trainable!;
      expect(t.sha256, 'cd');
      expect(t.problems(), isEmpty);
      expect(t.weightShapes['w1'], [3, 2]);
      expect(t.fineTune.learningRate, 0.05);
      expect(t.fineTune.minHoursBetweenRuns, 24);
    });

    test('a model without one has none', () {
      expect(ModelManifest.fromJson(manifestJson()).trainable, isNull);
    });

    test('a malformed block is refused', () {
      expect(
        () => ModelManifest.fromJson({...manifestJson(), 'trainable': 'x'}),
        throwsFormatException,
      );
      expect(
        () => TrainableManifest.fromJson({
          ...trainableJson(),
          'weights': {
            'w1': [0, 2],
          },
        }),
        throwsFormatException,
      );
    });

    test('lists what stops fine-tuning', () {
      final t = TrainableManifest.fromJson(
        trainableJson(
          signatures: ['infer'],
          fineTune: {
            'learning_rate': 0.05,
            'epochs': 1,
            'batch_size': 1,
            'max_examples': 2,
            'min_examples': 5,
            'min_hours_between_runs': 24,
          },
        ),
      );
      expect(t.problems(), [
        'no train signature',
        'no save signature',
        'no restore signature',
        'fine-tune settings out of range',
      ]);
    });
  });

  group('TunedWeights', () {
    TunedWeights tuned({String sha = 'cd', Map<String, Float32List>? w}) =>
        TunedWeights(
          trainableSha256: sha,
          trainedAt: now,
          exampleCount: 7,
          weights: w ?? FakeTrainableRuntime().save(),
        );

    test('round-trips through JSON', () {
      final back = TunedWeights.fromJson(tuned().toJson())!;
      expect(back.trainableSha256, 'cd');
      expect(back.trainedAt, now);
      expect(back.exampleCount, 7);
      expect(back.weights['w1'], tuned().weights['w1']);
      expect(back.fits(model().manifest), isTrue);
    });

    test('only fits the model it was learned on, with its shapes', () {
      final m = model().manifest;
      expect(tuned(sha: 'ef').fits(m), isFalse);
      final short = {...tuned().weights, 'w2': Float32List(3)};
      expect(tuned(w: short).fits(m), isFalse);
      final nan = {
        ...tuned().weights,
        'b2': Float32List.fromList([double.nan, 0]),
      };
      expect(tuned(w: nan).fits(m), isFalse);
    });

    test('a malformed record reads as none', () {
      expect(TunedWeights.fromJson({'trainable_sha256': 'cd'}), isNull);
      expect(
        TunedWeights.fromJson({
          ...tuned().toJson(),
          'weights': {'w1': 'not base64!'},
        }),
        isNull,
      );
    });
  });

  group('ModelFineTuner', () {
    late FakeTrainableRuntime runtime;
    late MemoryStore store;
    late int opened;

    ModelFineTuner tuner([TrainableModel? m]) => ModelFineTuner(
      model: m ?? model(),
      open: (bytes, w) {
        opened++;
        expect(w, width);
        return runtime;
      },
      store: store,
      now: () => now,
      random: Random(1),
    );

    setUp(() {
      runtime = FakeTrainableRuntime();
      store = MemoryStore();
      opened = 0;
    });

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
      ];
      expect(await tuner().fineTune(examples), isFalse);
      expect(opened, 0);
      expect(store.writes, 0);
    });

    test('trains on the latest examples with the manifest settings', () async {
      final examples = [
        for (var i = 0; i < 12; i++)
          example(i, label: i.isEven ? 'groceries' : 'eating_out'),
      ];
      expect(await tuner().fineTune(examples), isTrue);

      // 10 most recent, 3 epochs of batches of 4: 4 + 4 + 2.
      expect(runtime.batches, hasLength(9));
      expect(runtime.batches.every((b) => b.$3 == 0.05), isTrue);
      final seen = {
        for (final b in runtime.batches.take(3))
          for (final row in b.$1) row.first,
      };
      expect(seen, {for (var i = 2; i < 12; i++) i});
      for (final (rows, labels, _) in runtime.batches) {
        for (var j = 0; j < rows.length; j++) {
          expect(labels[j], rows[j].first.isEven ? 0 : 1);
        }
      }

      expect(runtime.closed, isTrue);
      final saved = store.weights!;
      expect(saved.trainableSha256, 'cd');
      expect(saved.exampleCount, 10);
      expect(saved.trainedAt, now);
      expect(saved.fits(model().manifest), isTrue);
    });

    test('keeps nothing when training diverges', () async {
      runtime.loss = double.nan;
      final examples = [for (var i = 0; i < 6; i++) example(i)];
      expect(await tuner().fineTune(examples), isFalse);
      expect(store.writes, 0);
      expect(runtime.closed, isTrue);
    });

    test('keeps nothing when the saved weights do not fit', () async {
      runtime = FakeTrainableRuntime(savedShapes: {'w1': shapes['w1']!});
      final examples = [for (var i = 0; i < 6; i++) example(i)];
      expect(await tuner().fineTune(examples), isFalse);
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
