import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/categories/default_categories.dart';
import 'package:pesaclarity/src/domain/categoriser/categoriser.dart';
import 'package:pesaclarity/src/domain/categoriser/features.dart';
import 'package:pesaclarity/src/domain/categoriser/learning.dart';
import 'package:pesaclarity/src/domain/categoriser/model_manifest.dart';
import 'package:pesaclarity/src/domain/categoriser/trainable.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ml/plain_weights.dart';
import 'package:pesaclarity/src/features/categoriser/data/model_store.dart';
import 'package:pesaclarity/src/features/categoriser/data/rayo_categoriser_runtime.dart';

import '../../domain/categoriser/trainable_test.dart' show MemoryStore;

/// The bundled categoriser (`assets/models/categoriser/categoriser.weights`),
/// run here as in the app: on rayo, whose build hook compiles its C for the
/// host.
///
/// tool/categoriser_decodes.py ran the same file on the app's own rayo
/// library (the commit the app pins, as its build hook compiles it), on
/// these very rows, and checked it against the PyTorch model it was
/// quantised from. The app's outputs must be those bit for bit on the
/// platform they were recorded on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Uint8List?> asset(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object {
      return null;
    }
  }

  Future<Map<String, Object?>> manifestJson() async => (jsonDecode(
    utf8.decode((await asset('$categoriserModelFolder/$modelManifestFile'))!),
  ) as Map).cast<String, Object?>();

  Future<Uint8List> weights() async =>
      (await asset('$categoriserModelFolder/categoriser.weights'))!;

  final recorded = jsonDecode(
    File('test/fixtures/categoriser/categoriser_decodes.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  final readings = {
    for (final r
        in (recorded['readings']! as List).cast<Map<String, Object?>>())
      r['id'] as String: r.cast<String, Object?>(),
  };
  final rows = _vectorRows();
  final missing = <String>[];
  tearDownAll(() => _saveMissing(missing, rows));
  const config = FeatureConfig();

  test(
    'the manifest is of the bundled weights, and this app reads it',
    () async {
      final json = await manifestJson();
      final bytes = await weights();
      final m = ModelManifest.fromJson(json);
      expect(m.incompatibilities(), isEmpty);
      expect(m.weightsFile, 'categoriser.weights');
      expect(bytes.length, m.weightsSizeBytes);
      expect(sha256.convert(bytes).toString(), m.weightsSha256);
      expect(recorded['weights_sha256'], m.weightsSha256);
      expect(m.featureConfig.width, config.width);
      expect(m.fineTune!.problems(), isEmpty);
      final plain = PlainWeights.parse(bytes);
      expect(plain.model, 'categoriser');
      expect(plain.sourceSha256, (json['source']! as Map)['sha256']);
    },
  );

  test('its labels are the app\'s category keys', () async {
    final labels = ModelLabels.fromJson(
      (jsonDecode(
        utf8.decode((await asset('$categoriserModelFolder/$modelLabelsFile'))!),
      ) as Map).cast<String, Object?>(),
    );
    final keys = {for (final c in defaultCategories) c.key};
    expect(labels.labels, hasLength(27));
    expect(labels.labels.where((l) => !keys.contains(l)), isEmpty);
  });

  test('the app loads it on rayo, ready to fine-tune', () async {
    final loaded = await loadCategoriser(
      readAsset: asset,
      openRuntime: openCategoriserRuntime,
    );
    addTearDown(loaded.categoriser.close);
    expect(loaded.status, ModelStatus.loaded, reason: '${loaded.reasons}');
    expect(loaded.categoriser.source, SuggestionSource.model);
    expect(loaded.tuned, isFalse);
    expect(loaded.fineTunable, isNotNull);
    final scores = loaded.categoriser.score(
      CategoriserInput(
        payee: 'DEMO FRESH MART TILL 000123',
        amountMinor: 120000,
        isInflow: false,
        occurredAt: DateTime.utc(2026, 3, 18, 9),
      ),
    );
    expect(scores, hasLength(27));
    expect(scores.fold(0.0, (a, s) => a + s.confidence), closeTo(1, 1e-5));
  });

  test(
    'with the model loaded, the rules still settle the message types',
    () async {
      final loaded = await loadCategoriser(
        readAsset: asset,
        openRuntime: openCategoriserRuntime,
      );
      addTearDown(loaded.categoriser.close);
      expect(loaded.status, ModelStatus.loaded);
      CategoriserInput input(String payee, TransactionKind kind) =>
          CategoriserInput(
            payee: payee,
            amountMinor: 3000,
            isInflow: false,
            occurredAt: DateTime.utc(2026, 11, 19, 9),
            kind: kind,
          );
      for (final (kind, key) in [
        (TransactionKind.fulizaRepayment, 'fuliza_repayment'),
        (TransactionKind.airtime, 'airtime_data'),
        (TransactionKind.charge, 'fees_charges'),
      ]) {
        final best = loaded.categoriser.score(input('SAFARICOM', kind)).first;
        expect(best.key, key, reason: '$kind');
        expect(best.source, SuggestionSource.rules, reason: '$kind');
      }
      // An unfamiliar payee goes to the model, all 27 labels.
      final scores = loaded.categoriser.score(
        input('DEMO FRESH MART TILL 000123', TransactionKind.till),
      );
      expect(scores, hasLength(27));
      expect(scores.first.source, isNull);
      expect(loaded.categoriser.source, SuggestionSource.model);
    },
  );

  // rayo gives the same floats on every kernel and thread count, and from
  // any compiler and flags (it is built with -ffp-contract=off). Another
  // platform's C library may round exp differently in the last bit, so
  // there only nearly.
  final exact = recorded['abi'] == Abi.current().toString();
  test(
    exact
        ? 'rayo gives the recorded outputs bit for bit'
        : 'rayo gives the recorded outputs within $_otherPlatforms',
    () async {
      final model = RayoCategoriser.open(await weights(), config.width);
      addTearDown(model.close);
      expect(model.outputSize, 27);
      for (final MapEntry(key: id, value: row) in rows.entries) {
        final r = readings[id];
        if (r == null || !_same((r['input']! as List).cast<int>(), row)) {
          missing.add(id);
          continue;
        }
        final got = model.run(row);
        final want = _float32s(r['category']);
        if (exact) {
          expect(got, want, reason: id);
        } else {
          expect(_argmax(got), _argmax(want), reason: id);
          for (final (i, w) in want.indexed) {
            expect(got[i], closeTo(w, _otherPlatforms), reason: id);
          }
        }
      }
      expect(
        missing,
        isEmpty,
        reason: 'no rayo recording: run tool/categoriser_decodes.py',
      );
    },
  );

  test('a run leaves nothing behind for the next', () async {
    final model = RayoCategoriser.open(await weights(), config.width);
    addTearDown(model.close);
    final a = rows.values.first;
    final b = rows.values.last;
    final first = model.run(a);
    model.run(b);
    expect(model.run(a), first);
  });

  test('the network in Dart is close to rayo, with the same labels', () async {
    final network = CategoriserNetwork.parse(await weights(), config);
    final dart = DartCategoriserRuntime(network);
    for (final r in readings.values) {
      final want = _float32s(r['category']);
      final got = dart.run((r['input']! as List).cast<int>());
      // rayo quantises the hidden layer's input to int8; Dart keeps it.
      for (final (i, w) in want.indexed) {
        expect(got[i], closeTo(w, _dartTolerance), reason: '${r['id']}');
      }
      if (_margin(want) > _labelMargin) {
        expect(_argmax(got), _argmax(want), reason: '${r['id']}');
      }
    }
  });

  group('fine-tuning the bundled model', () {
    late FineTunableModel model;
    late MemoryStore store;
    final now = DateTime.utc(2026, 11, 19, 9);

    setUp(() async {
      final loaded = await loadCategoriser(
        readAsset: asset,
        openRuntime: openCategoriserRuntime,
      );
      loaded.categoriser.close();
      model = loaded.fineTunable!;
      store = MemoryStore();
    });

    test('learns the person\'s choice and suggests with it', () async {
      final labels = model.labels;
      final runtime = DartCategoriserRuntime(model.network);
      // Rows the shipped model does not put in `giving`.
      final row = rows['till_basic']!;
      final giving = labels.indexOf('giving');
      final before = runtime.run(row)[giving];
      expect(before, lessThan(0.5));
      final examples = [
        for (var i = 0; i < model.manifest.settings.minExamples * 2; i++)
          TrainingExample(
            features: row,
            label: 'giving',
            featureSchemaVersion: model.featureSchemaVersion,
          ),
      ];
      final tuner = ModelFineTuner(
        model: model,
        store: store,
        now: () => now,
        random: Random(1),
      );
      expect(await tuner.fineTune(examples), isTrue);
      final saved = store.weights!;
      expect(saved.weightsSha256, model.weightsSha256);
      expect(saved.weights.keys, FineTuneManifest.tensorNames);
      expect(saved.fits(model), isTrue);

      // Stored, read back and loaded as the app does.
      final back = TunedWeights.fromJson(
        jsonDecode(jsonEncode(saved.toJson())) as Map<String, Object?>,
      )!;
      final loaded = await loadCategoriser(
        readAsset: asset,
        openRuntime: openCategoriserRuntime,
        tuned: back,
      );
      expect(loaded.tuned, isTrue);
      final after = loaded.categoriser.score(
        CategoriserInput(
          payee: 'DEMO FRESH MART TILL 000123',
          amountMinor: 120000,
          isInflow: false,
          occurredAt: DateTime.utc(2026, 3, 18, 9),
        ),
      );
      final tunedGiving = after.firstWhere((s) => s.key == 'giving');
      expect(tunedGiving.confidence, greaterThan(before));
      expect(after.first.key, 'giving');
      // The shipped model is unchanged: each run starts from it.
      expect(runtime.run(row)[giving], before);
    });

    test('weights tuned on another file do not fit', () {
      final tuned = TunedWeights(
        weightsSha256: 'ef' * 32,
        trainedAt: now,
        exampleCount: 10,
        weights: model.network.shipped.toNamed(),
      );
      expect(tuned.fits(model), isFalse);
      final same = TunedWeights(
        weightsSha256: model.weightsSha256,
        trainedAt: now,
        exampleCount: 10,
        weights: model.network.shipped.toNamed(),
      );
      expect(same.fits(model), isTrue);
    });
  });
}

/// How far rayo's outputs may be from the recordings on a platform other
/// than the one they were recorded on.
const _otherPlatforms = 1e-5;

/// How far the Dart network may be from rayo, and the margin between the
/// two best beyond which its label must be rayo's (the export's, against
/// torch).
const _dartTolerance = 0.05;
const _labelMargin = 0.2;

/// The encoded rows of the feature vectors, by case id.
Map<String, List<int>> _vectorRows() {
  final doc = jsonDecode(
    File('test/fixtures/categoriser/feature_vectors.v1.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  return {
    for (final c in (doc['cases']! as List).cast<Map<String, Object?>>())
      c['id']! as String: ((c['expected']! as Map)['features']! as List)
          .cast<int>(),
  };
}

int _argmax(List<double> v) {
  var best = 0;
  for (var i = 1; i < v.length; i++) {
    if (v[i] > v[best]) best = i;
  }
  return best;
}

double _margin(List<double> v) {
  final sorted = [...v]..sort();
  return sorted[sorted.length - 1] - sorted[sorted.length - 2];
}

List<double> _float32s(Object? values) => Float32List.fromList([
  for (final v in values! as List) (v! as num).toDouble(),
]);

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// With `CATEGORISER_RECORD=path`, writes the rows with no recording for
/// tool/categoriser_decodes.py.
void _saveMissing(List<String> ids, Map<String, List<int>> rows) {
  final path = Platform.environment['CATEGORISER_RECORD'];
  if (path == null) return;
  File(path).writeAsStringSync(
    jsonEncode([
      for (final id in ids.toSet()) {'id': id, 'input': rows[id]},
    ]),
  );
}
