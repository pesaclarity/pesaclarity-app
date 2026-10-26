import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/categoriser/categoriser.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/features/categoriser/data/model_store.dart';

import '../../domain/categoriser/categoriser_test.dart'
    show FakeRuntime, manifestJson;

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

  Future<void> install({
    Map<String, Object?> overrides = const {},
    String? sha,
    int version = 1,
  }) async {
    File('${folder.path}/categoriser.tflite').writeAsBytesSync(model);
    final manifest = {
      ...manifestJson(version: version),
      'model_sha256': sha ?? await sha256Hex(model),
      'model_size_bytes': model.length,
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
}
