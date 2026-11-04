import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/categoriser/categoriser.dart';
import 'package:pesaclarity/src/domain/categoriser/trainable.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/features/categoriser/data/model_store.dart';

import '../../domain/categoriser/categoriser_test.dart'
    show FakeRuntime, manifestJson;
import '../../domain/categoriser/trainable_test.dart'
    show FakeTrainableRuntime, trainableJson;

void main() {
  late Directory folder;
  final model = Uint8List.fromList(List.generate(64, (i) => i));
  var opened = 0;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('categoriser');
    opened = 0;
  });
  tearDown(() => folder.deleteSync(recursive: true));

  TfliteRuntime open(Uint8List bytes, int width) {
    opened++;
    expect(width, 13);
    return FakeRuntime([0.2, 0.8]);
  }

  final trainableBytes = Uint8List.fromList(List.generate(64, (i) => 200 - i));

  Future<void> install({
    Map<String, Object?> overrides = const {},
    String? sha,
    int version = 1,
    bool trainable = false,
    String? trainableSha,
  }) async {
    File('${folder.path}/categoriser.tflite').writeAsBytesSync(model);
    File('${folder.path}/categoriser-train.tflite')
        .writeAsBytesSync(trainableBytes);
    final manifest = {
      ...manifestJson(version: version),
      'model_sha256': sha ?? await sha256Hex(model),
      'model_size_bytes': model.length,
      if (trainable)
        'trainable': trainableJson(
          sha: trainableSha ?? await sha256Hex(trainableBytes),
        ),
      ...overrides,
    };
    File('${folder.path}/$modelManifestFile')
        .writeAsStringSync(jsonEncode(manifest));
    File('${folder.path}/$modelLabelsFile').writeAsStringSync(
      jsonEncode({
        'version': 1,
        'labels': ['groceries', 'eating_out'],
      }),
    );
  }

  test('without a model the rules fallback is used', () async {
    final loaded = await loadCategoriser(folder, openRuntime: open);
    expect(loaded.status, ModelStatus.notInstalled);
    expect(loaded.categoriser.source, SuggestionSource.rules);
    expect(opened, 0);
  });

  test('loads a model whose manifest and hash match', () async {
    await install();
    final loaded = await loadCategoriser(folder, openRuntime: open);
    expect(loaded.status, ModelStatus.loaded, reason: '${loaded.reasons}');
    expect(loaded.categoriser.source, SuggestionSource.model);
  });

  test('refuses a feature schema it cannot feed without opening it', () async {
    await install(version: 2);
    final loaded = await loadCategoriser(folder, openRuntime: open);
    expect(loaded.status, ModelStatus.refused);
    expect(loaded.categoriser.source, SuggestionSource.rules);
    expect(loaded.reasons.single, contains('schema version 2'));
    expect(opened, 0);
  });

  test('refuses a model whose SHA-256 differs from the manifest', () async {
    await install(sha: '00' * 32);
    final loaded = await loadCategoriser(folder, openRuntime: open);
    expect(loaded.status, ModelStatus.refused);
    expect(opened, 0);
  });

  test('refuses a model file outside its folder', () async {
    await install(overrides: {'model_file': '../categoriser.tflite'});
    final loaded = await loadCategoriser(folder, openRuntime: open);
    expect(loaded.status, ModelStatus.refused);
  });

  test('falls back when the runtime cannot open the model', () async {
    await install();
    final loaded = await loadCategoriser(
      folder,
      openRuntime: (_, _) => throw StateError('no native library'),
    );
    expect(loaded.status, ModelStatus.refused);
    expect(loaded.categoriser.source, SuggestionSource.rules);
  });

  group('trainable copy', () {
    late FakeTrainableRuntime trainableRuntime;
    var trainableOpened = 0;

    setUp(() {
      trainableRuntime = FakeTrainableRuntime()..probs = [0.9, 0.1];
      trainableOpened = 0;
    });

    TrainableRuntime openTrainable(Uint8List bytes, int width) {
      trainableOpened++;
      expect(bytes, trainableBytes);
      return trainableRuntime;
    }

    Future<TunedWeights> tunedFor(String sha) async => TunedWeights(
      trainableSha256: sha,
      trainedAt: DateTime.utc(2026, 11, 4),
      exampleCount: 12,
      weights: FakeTrainableRuntime().save(),
    );

    test('is offered for fine-tuning when it checks out', () async {
      await install(trainable: true);
      final loaded = await loadCategoriser(
        folder,
        openRuntime: open,
        openTrainable: openTrainable,
      );
      expect(loaded.status, ModelStatus.loaded);
      expect(loaded.trainable?.bytes, trainableBytes);
      expect(loaded.trainable?.labels, ['groceries', 'eating_out']);
      expect(loaded.tuned, isFalse);
      expect(trainableOpened, 0);
      expect(opened, 1);
    });

    test(
      'is ignored when its hash differs, and the model still loads',
      () async {
        await install(trainable: true, trainableSha: '00' * 32);
        final loaded = await loadCategoriser(
          folder,
          openRuntime: open,
          openTrainable: openTrainable,
          tuned: await tunedFor('00' * 32),
        );
        expect(loaded.status, ModelStatus.loaded);
        expect(loaded.trainable, isNull);
        expect(loaded.tuned, isFalse);
        expect(trainableOpened, 0);
      },
    );

    test('suggests with tuned weights that fit it', () async {
      await install(trainable: true);
      final tuned = await tunedFor(await sha256Hex(trainableBytes));
      final loaded = await loadCategoriser(
        folder,
        openRuntime: open,
        openTrainable: openTrainable,
        tuned: tuned,
      );
      expect(loaded.tuned, isTrue);
      expect(trainableRuntime.restored, tuned.weights);
      expect(opened, 0);
      final scores = loaded.categoriser.score(
        CategoriserInput(
          payee: 'Naivas',
          amountMinor: 50000,
          isInflow: false,
          occurredAt: DateTime.utc(2026, 11, 4),
        ),
      );
      expect(scores.first.key, 'groceries');
    });

    test('ignores tuned weights from another model', () async {
      await install(trainable: true);
      final loaded = await loadCategoriser(
        folder,
        openRuntime: open,
        openTrainable: openTrainable,
        tuned: await tunedFor('ef' * 32),
      );
      expect(loaded.tuned, isFalse);
      expect(trainableOpened, 0);
      expect(opened, 1);
    });

    test('falls back to the installed weights when restoring fails', () async {
      await install(trainable: true);
      final loaded = await loadCategoriser(
        folder,
        openRuntime: open,
        openTrainable: (_, _) => throw StateError('no signature runner'),
        tuned: await tunedFor(await sha256Hex(trainableBytes)),
      );
      expect(loaded.status, ModelStatus.loaded);
      expect(loaded.tuned, isFalse);
      expect(opened, 1);
    });
  });
}
