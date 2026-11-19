import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/categoriser/categoriser.dart';
import 'package:pesaclarity/src/domain/categoriser/features.dart';
import 'package:pesaclarity/src/domain/categoriser/trainable.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/features/categoriser/data/model_store.dart';

import '../../domain/categoriser/categoriser_test.dart'
    show FakeRuntime, manifestJson;
import '../../domain/categoriser/trainable_test.dart'
    show fineTuneJson, tinyWeights;

void main() {
  late Map<String, Uint8List> files;
  var opened = 0;
  var reads = <String>[];

  Future<Uint8List?> read(String path) async {
    reads.add(path);
    return files[path];
  }

  setUp(() {
    files = {};
    opened = 0;
    reads = [];
  });

  CategoriserRuntime open(Uint8List bytes, FeatureConfig config) {
    opened++;
    expect(config.width, 13);
    expect(bytes, files['$categoriserModelFolder/categoriser.weights']);
    return FakeRuntime([0.2, 0.8]);
  }

  /// The tiny network's file, its manifest and two labels.
  Future<void> install({
    Map<String, Object?> overrides = const {},
    String? sha,
    int version = 1,
    bool fineTune = false,
    Map<String, Object?>? fineTuneBlock,
    Uint8List? weights,
  }) async {
    final bytes = weights ?? tinyWeights();
    files['$categoriserModelFolder/categoriser.weights'] = bytes;
    final manifest = {
      ...manifestJson(version: version),
      'feature_config': {'max_tokens': 8, 'hash_buckets': 16},
      'weights_sha256': sha ?? await sha256Hex(bytes),
      'weights_size_bytes': bytes.length,
      if (fineTune) 'fine_tune': fineTuneBlock ?? fineTuneJson(),
      ...overrides,
    };
    files['$categoriserModelFolder/$modelManifestFile'] = utf8.encode(
      jsonEncode(manifest),
    );
    files['$categoriserModelFolder/$modelLabelsFile'] = utf8.encode(
      jsonEncode({
        'version': 1,
        'labels': ['groceries', 'eating_out'],
      }),
    );
  }

  test('without a model the rules fallback is used', () async {
    final loaded = await loadCategoriser(readAsset: read, openRuntime: open);
    expect(loaded.status, ModelStatus.notInstalled);
    expect(loaded.categoriser.source, SuggestionSource.rules);
    expect(opened, 0);
  });

  test('loads a model whose manifest and hash match', () async {
    await install();
    final loaded = await loadCategoriser(readAsset: read, openRuntime: open);
    expect(loaded.status, ModelStatus.loaded, reason: '${loaded.reasons}');
    expect(loaded.categoriser.source, SuggestionSource.model);
    expect(loaded.fineTunable, isNull, reason: 'no fine_tune block');
    expect(opened, 1);
  });

  test('refuses a model that fits when the build has no runtime', () async {
    await install(fineTune: true);
    final loaded = await loadCategoriser(readAsset: read, openRuntime: null);
    expect(loaded.status, ModelStatus.refused);
    expect(loaded.reasons, ['this build has no runtime for the model']);
    expect(loaded.categoriser.source, SuggestionSource.rules);
    expect(loaded.fineTunable, isNull);
  });

  test('refuses a feature schema it cannot feed without opening it', () async {
    await install(version: 2);
    final loaded = await loadCategoriser(readAsset: read, openRuntime: open);
    expect(loaded.status, ModelStatus.refused);
    expect(loaded.categoriser.source, SuggestionSource.rules);
    expect(loaded.reasons.single, contains('schema version 2'));
    expect(opened, 0);
    expect(reads, isNot(contains(endsWith('.weights'))));
  });

  test('refuses a weights format it does not read', () async {
    await install(overrides: {'weights_format_version': 2});
    final loaded = await loadCategoriser(readAsset: read, openRuntime: open);
    expect(loaded.status, ModelStatus.refused);
    expect(loaded.reasons, ['weights format 2; this app reads 1']);
    expect(opened, 0);
  });

  test('refuses the TFLite-era manifest', () async {
    await install();
    final json = jsonDecode(
      utf8.decode(files['$categoriserModelFolder/$modelManifestFile']!),
    ) as Map<String, Object?>;
    json
      ..remove('weights_file')
      ..['model_file'] = 'categoriser.tflite';
    files['$categoriserModelFolder/$modelManifestFile'] = utf8.encode(
      jsonEncode(json),
    );
    final loaded = await loadCategoriser(readAsset: read, openRuntime: open);
    expect(loaded.status, ModelStatus.refused);
    expect(loaded.reasons.single, contains('weights_file'));
  });

  test('refuses weights whose SHA-256 differs from the manifest', () async {
    await install(sha: '00' * 32);
    final loaded = await loadCategoriser(readAsset: read, openRuntime: open);
    expect(loaded.status, ModelStatus.refused);
    expect(loaded.reasons, ['weights SHA-256 does not match the manifest']);
    expect(opened, 0);
  });

  test('refuses weights of another size', () async {
    await install(overrides: {'weights_size_bytes': 10});
    final loaded = await loadCategoriser(readAsset: read, openRuntime: open);
    expect(loaded.status, ModelStatus.refused);
    expect(loaded.reasons.single, startsWith('weights size'));
    expect(opened, 0);
  });

  test('refuses a weights file outside its folder', () async {
    await install(overrides: {'weights_file': '../categoriser.weights'});
    final loaded = await loadCategoriser(readAsset: read, openRuntime: open);
    expect(loaded.status, ModelStatus.refused);
    expect(reads, isNot(contains(contains('..'))));
  });

  test('falls back when the runtime cannot open the model', () async {
    await install();
    final loaded = await loadCategoriser(
      readAsset: read,
      openRuntime: (_, _) => throw StateError('no native library'),
    );
    expect(loaded.status, ModelStatus.refused);
    expect(loaded.categoriser.source, SuggestionSource.rules);
  });

  group('fine-tuning', () {
    Future<TunedWeights> tunedFor(String sha) async => TunedWeights(
      weightsSha256: sha,
      trainedAt: DateTime.utc(2026, 11, 4),
      exampleCount: 12,
      weights: _favourGroceries(),
    );

    final row = CategoriserInput(
      payee: 'Naivas',
      amountMinor: 50000,
      isInflow: false,
      occurredAt: DateTime.utc(2026, 11, 4),
    );

    test('is offered when the fine_tune block fits the weights', () async {
      await install(fineTune: true);
      final loaded = await loadCategoriser(readAsset: read, openRuntime: open);
      expect(loaded.status, ModelStatus.loaded);
      final model = loaded.fineTunable!;
      expect(model.weightsSha256, await sha256Hex(tinyWeights()));
      expect(model.labels, ['groceries', 'eating_out']);
      expect(model.width, 13);
      expect(loaded.tuned, isFalse);
      expect(opened, 1);
    });

    test('is not offered for another spec version or other shapes', () async {
      for (final block in [
        fineTuneJson(specVersion: 2),
        fineTuneJson(
          weights: {
            'hidden.kernel': [4, 6],
            'hidden.bias': [4],
            'category.kernel': [2, 4],
            'category.bias': [2],
          },
        ),
      ]) {
        await install(fineTune: true, fineTuneBlock: block);
        final loaded = await loadCategoriser(
          readAsset: read,
          openRuntime: open,
          tuned: await tunedFor(await sha256Hex(tinyWeights())),
        );
        expect(loaded.status, ModelStatus.loaded);
        expect(loaded.fineTunable, isNull);
        expect(loaded.tuned, isFalse);
      }
    });

    test('suggests in Dart with tuned weights that fit it', () async {
      await install(fineTune: true);
      final loaded = await loadCategoriser(
        readAsset: read,
        openRuntime: open,
        tuned: await tunedFor(await sha256Hex(tinyWeights())),
      );
      expect(loaded.tuned, isTrue);
      expect(opened, 0);
      // The fake runtime says eating_out; the tuned weights groceries.
      expect(loaded.categoriser.score(row).first.key, 'groceries');
    });

    test('ignores tuned weights from another weights file', () async {
      await install(fineTune: true);
      final loaded = await loadCategoriser(
        readAsset: read,
        openRuntime: open,
        tuned: await tunedFor('ef' * 32),
      );
      expect(loaded.tuned, isFalse);
      expect(opened, 1);
      expect(loaded.categoriser.score(row).first.key, 'eating_out');
    });
  });
}

/// The tiny network's trained tensors with the groceries bias far ahead.
Map<String, Float32List> _favourGroceries() {
  final w = {
    'hidden.kernel': Float32List(18),
    'hidden.bias': Float32List(3),
    'category.kernel': Float32List(6),
    'category.bias': Float32List.fromList([5, -5]),
  };
  return w;
}
