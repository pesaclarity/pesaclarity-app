import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/categoriser/learning.dart';

class _Log
    implements OnDeviceTrainer, FederatedUpdateTrainer, ModelUpdateUploader {
  final calls = <String>[];
  void Function()? onCompute;

  @override
  Future<void> fineTune(List<TrainingExample> examples) async =>
      calls.add('fineTune ${examples.length}');

  @override
  Future<ModelUpdate> computeUpdate(List<TrainingExample> examples) async {
    calls.add('computeUpdate');
    onCompute?.call();
    return ModelUpdate(payload: Uint8List(4), exampleCount: examples.length);
  }

  @override
  Future<void> upload(ModelUpdate update) async => calls.add('upload');
}

const _example = TrainingExample(
  features: [1, 2, 3, 0, 0, 0, 0, 0, 5, 0, 3, 2, 1],
  label: 'groceries',
  featureSchemaVersion: 1,
);

void main() {
  late _Log log;
  late bool optedIn;
  late int reads;

  setUp(() {
    log = _Log();
    optedIn = false;
    reads = 0;
  });

  CategoriserLearning learning({bool withTrainers = true}) =>
      CategoriserLearning(
        optedIn: () => optedIn,
        examples: () async {
          reads++;
          return const [_example];
        },
        trainer: withTrainers ? log : null,
        federated: withTrainers ? log : null,
        uploader: withTrainers ? log : null,
      );

  test('without opt-in nothing is read, trained or sent', () async {
    expect(await learning().run(), LearningOutcome.notOptedIn);
    expect(reads, 0);
    expect(log.calls, isEmpty);
  });

  test('opted in with no trainer in this build does nothing', () async {
    optedIn = true;
    expect(
      await learning(withTrainers: false).run(),
      LearningOutcome.unavailable,
    );
    expect(reads, 0);
  });

  test('opted in: fine-tunes, then sends an update', () async {
    optedIn = true;
    expect(await learning().run(), LearningOutcome.uploaded);
    expect(log.calls, ['fineTune 1', 'computeUpdate', 'upload']);
  });

  test('switching consent off mid-run stops the upload', () async {
    optedIn = true;
    log.onCompute = () => optedIn = false;
    expect(await learning().run(), LearningOutcome.notOptedIn);
    expect(log.calls, isNot(contains('upload')));
  });
}
