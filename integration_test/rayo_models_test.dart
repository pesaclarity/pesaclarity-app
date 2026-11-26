// On a phone or simulator, each bundled model runs on rayo, with no Dart,
// rules or template stand-in, and gives the outputs recorded in
// test/fixtures. Run it on a device:
//
//   flutter test integration_test/rayo_models_test.dart -d <device>
//
// The recordings come from the host the tool/*_decodes.py scripts ran on;
// another platform's C library may round exp differently in the last bit,
// so the most likely label must match and the probabilities nearly.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pesaclarity/src/core/ml/model_engines.dart';
import 'package:pesaclarity/src/domain/ask/model_reply_writer.dart';
import 'package:pesaclarity/src/domain/categoriser/model_manifest.dart';
import 'package:pesaclarity/src/features/ask/data/ask_model_store.dart';
import 'package:pesaclarity/src/features/ask/data/rayo_ask_runtimes.dart';
import 'package:pesaclarity/src/features/categoriser/data/model_store.dart';
import 'package:pesaclarity/src/features/categoriser/data/rayo_categoriser_runtime.dart';
import 'package:pesaclarity/src/features/review/data/rayo_reader_runtime.dart';
import 'package:pesaclarity/src/features/review/data/reader_store.dart';
import 'package:rayo/rayo.dart';

import 'rayo_model_goldens.dart';

/// How far a probability may be from the recording.
const _tolerance = 1e-4;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<Uint8List> asset(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<Map<String, Object?>> json(String path) async =>
      (jsonDecode(utf8.decode(await asset(path))) as Map)
          .cast<String, Object?>();

  Map<String, Object?> recorded(String text) =>
      (jsonDecode(text) as Map).cast<String, Object?>();

  final engines = ModelEngines();

  test('rayo loads on this device', () {
    expect(rayoAvailable(), isTrue, reason: "rayo's library did not load");
    debugPrint('rayo ${rayoVersion()}');
  });

  test('the Ask reader runs on rayo and gives the recorded outputs', () async {
    final manifest = await json('$askModelFolder/$askReaderManifestFile');
    final golden = recorded(askReaderDecodes);
    expect(golden['weights_sha256'], manifest['weights_sha256']);
    final model = openAskReader(
      await asset('$askModelFolder/${manifest['weights_file']}'),
      onlyRayo: true,
      engines: engines,
    );
    addTearDown(model.close);
    expect(model, isA<RayoAskReader>());
    debugPrint('Ask reader: ${engines.of(OnPhoneModel.askReader).engine}');
    final readings = golden['readings']! as List;
    expect(readings, isNotEmpty);
    final check = _Checker();
    for (final r in readings.cast<Map<String, Object?>>()) {
      final (slots, intent) = model.run((r['input']! as List).cast<int>());
      final q = r['question'];
      check(intent, r['intent']!, 'intent of "$q"');
      for (final (t, want) in (r['slots']! as List).indexed) {
        check(slots[t], want as Object, 'slot of token $t of "$q"');
      }
    }
    check.done();
  });

  test(
    'the message reader runs on rayo and gives the recorded outputs',
    () async {
      final manifest = await json('$readerModelFolder/$readerManifestFile');
      final golden = recorded(messageReaderDecodes);
      expect(golden['weights_sha256'], manifest['weights_sha256']);
      final model = openMessageReader(
        await asset('$readerModelFolder/${manifest['weights_file']}'),
        engines: engines,
      );
      addTearDown(model.close);
      expect(model, isA<RayoMessageReader>());
      debugPrint(
        'Message reader: ${engines.of(OnPhoneModel.messageReader).engine}',
      );
      final readings = golden['readings']! as List;
      expect(readings, isNotEmpty);
      final check = _Checker();
      for (final r in readings.cast<Map<String, Object?>>()) {
        final (fields, kind) = model.run((r['input']! as List).cast<int>());
        final m = r['message'];
        check(kind, r['kind']!, 'kind of "$m"');
        for (final (t, want) in (r['fields']! as List).indexed) {
          check(fields[t], want as Object, 'field of token $t of "$m"');
        }
      }
      check.done();
    },
  );

  test('the categoriser runs on rayo and gives the recorded outputs', () async {
    final raw = await json('$categoriserModelFolder/$modelManifestFile');
    final manifest = ModelManifest.fromJson(raw);
    final golden = recorded(categoriserDecodes);
    expect(golden['weights_sha256'], manifest.weightsSha256);
    final model = openCategoriserRuntime(
      await asset('$categoriserModelFolder/${manifest.weightsFile}'),
      manifest.featureConfig,
      onlyRayo: true,
      engines: engines,
    );
    addTearDown(model.close);
    expect(model, isA<RayoCategoriser>());
    debugPrint('Categoriser: ${engines.of(OnPhoneModel.categoriser).engine}');
    final readings = golden['readings']! as List;
    expect(readings, isNotEmpty);
    final check = _Checker();
    for (final r in readings.cast<Map<String, Object?>>()) {
      final got = model.run((r['input']! as List).cast<int>());
      check(got, r['category']!, 'category of ${r['id']}');
    }
    check.done();
  });

  test('the Ask writer runs on rayo and decodes the same twice', () async {
    final raw = await json('$askModelFolder/$askWriterManifestFile');
    final manifest = AskWriterManifest.fromJson(raw);
    final golden = recorded(askWriterDecodes);
    expect(golden['model_sha256'], raw['model_sha256']);
    final model = openAskWriter(
      await asset('$askModelFolder/${manifest.weightsFile}'),
      manifest,
      onlyRayo: true,
      engines: engines,
    );
    addTearDown(model.close);
    expect(model, isA<RayoAskWriter>());
    debugPrint('Ask writer: ${engines.of(OnPhoneModel.askWriter).engine}');
    final decodes = (golden['decodes']! as List).take(8);
    for (final d in decodes.cast<Map<String, Object?>>()) {
      final request = WriterDecode(
        prefix: (d['prefix']! as List).cast<int>(),
        eos: manifest.eos,
        vocabSize: manifest.vocabSize,
        banned: const [],
        once: const [],
        needed: const [],
        seed: d['seed']! as int,
        mask: false,
      );
      final first = await model.decode(request);
      final second = await model.decode(request);
      expect(second, first, reason: 'decode of ${d['prefix']}');
      for (final id in first ?? const <int>[]) {
        expect(id, inInclusiveRange(0, manifest.vocabSize - 1));
      }
    }
  });
}

/// Compares outputs with recordings: the same most likely label, and each
/// probability within [_tolerance].
class _Checker {
  var worst = 0.0;
  var checked = 0;

  void call(List<double> got, Object want, String what) {
    final expected = [for (final v in want as List) (v as num).toDouble()];
    expect(got, hasLength(expected.length), reason: what);
    expect(_argmax(got), _argmax(expected), reason: what);
    for (var i = 0; i < got.length; i++) {
      // The recordings are float32.
      final w = Float32List.fromList([expected[i]])[0];
      worst = math.max(worst, (got[i] - w).abs());
    }
    checked++;
  }

  void done() {
    debugPrint('$checked outputs, worst difference $worst');
    expect(checked, greaterThan(0));
    expect(worst, lessThan(_tolerance));
  }
}

int _argmax(List<double> xs) {
  var best = 0;
  for (var i = 1; i < xs.length; i++) {
    if (xs[i] > xs[best]) best = i;
  }
  return best;
}
