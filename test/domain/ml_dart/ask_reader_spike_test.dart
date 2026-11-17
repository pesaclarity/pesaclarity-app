import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/ml_dart/ask_reader_spike.dart';

/// Spike: the pure-Dart Ask reader against the real model's outputs, recorded
/// with TFLite in test/fixtures/ask/ask_reader_decodes.json. The weights come
/// from the bundled ask-reader.tflite via tool/ask_reader_weights.py.
void main() {
  final recorded = jsonDecode(
    File('test/fixtures/ask/ask_reader_decodes.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final readings = (recorded['readings']! as List).cast<Map<String, Object?>>();
  final weights = PlainWeights.parse(
    File('test/fixtures/ask/ask-reader.weights').readAsBytesSync(),
  );
  final manifest = jsonDecode(
    File('assets/models/ask/ask-reader-manifest.json').readAsStringSync(),
  ) as Map<String, Object?>;

  int argmax(List<double> v) {
    var best = 0;
    for (var i = 1; i < v.length; i++) {
      if (v[i] > v[best]) best = i;
    }
    return best;
  }

  test('the weights are of the bundled reader', () {
    expect(weights.modelSha256, manifest['model_sha256']);
    expect(recorded['model_sha256'], manifest['model_sha256']);
  });

  // The fixture rounds to 5 decimals, so 5e-6 is a perfect match. With
  // TFLite's on-the-fly int8 quantisation copied, the worst value is about
  // 3e-5 off; plain floats are about 1e-2 off. Both give TFLite's labels.
  for (final (hybrid, simd, tolerance) in [
    (true, false, 1e-4),
    (false, false, 2e-2),
    (true, true, 1e-4),
    (false, true, 2e-2),
  ]) {
    test('${hybrid ? 'int8 as TFLite runs it' : 'plain floats'}'
        '${simd ? ', four lanes at a time' : ''}: '
        'same labels as TFLite on all ${readings.length} questions', () {
      final reader = DartAskReader(weights, hybrid: hybrid, simd: simd);
      var worst = 0.0;
      var same = 0;
      for (final r in readings) {
        final input = (r['input']! as List).cast<int>();
        final intent = (r['intent']! as List).cast<num>().map(
          (v) => v.toDouble(),
        );
        final slots = [
          for (final row in (r['slots']! as List).cast<List<Object?>>())
            row.cast<num>().map((v) => v.toDouble()).toList(),
        ];
        final (gotSlots, gotIntent) = reader.run(input);
        final wantIntent = intent.toList();
        var labels = argmax(gotIntent) == argmax(wantIntent);
        for (var i = 0; i < wantIntent.length; i++) {
          worst = math.max(worst, (gotIntent[i] - wantIntent[i]).abs());
        }
        for (var t = 0; t < slots.length; t++) {
          labels &= argmax(gotSlots[t]) == argmax(slots[t]);
          for (var j = 0; j < slots[t].length; j++) {
            worst = math.max(worst, (gotSlots[t][j] - slots[t][j]).abs());
          }
        }
        if (labels) same++;
      }
      // ignore: avoid_print
      print(
        'hybrid=$hybrid simd=$simd: $same/${readings.length} same labels, '
        'max |Dart - TFLite| probability ${worst.toStringAsExponential(2)}',
      );
      expect(same, readings.length);
      expect(worst, lessThan(tolerance));
    });
  }
}
