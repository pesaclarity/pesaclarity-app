// Spike: times the pure-Dart Ask reader on this computer.
//
//   dart run tool/spike/ask_reader_bench.dart
//   dart compile exe tool/spike/ask_reader_bench.dart -o build/ask_bench \
//     && build/ask_bench
//
// Prints the weight load time, the first question's time, the median time
// per question (one at a time) and the time for the whole fixture as a batch.

import 'dart:convert';
import 'dart:io';

import 'package:pesaclarity/src/domain/ml_dart/ask_reader_spike.dart';

void main(List<String> args) {
  final rounds = args.isEmpty ? 50 : int.parse(args.first);
  final readings =
      ((jsonDecode(
                File('test/fixtures/ask/ask_reader_decodes.json')
                    .readAsStringSync(),
              ) as Map<String, Object?>)['readings']!
              as List)
          .cast<Map<String, Object?>>();
  final inputs = [for (final r in readings) (r['input']! as List).cast<int>()];
  final bytes = File('test/fixtures/ask/ask-reader.weights').readAsBytesSync();

  for (final (hybrid, simd) in [
    (true, false),
    (false, false),
    (true, true),
    (false, true),
  ]) {
    final load = Stopwatch()..start();
    final reader = DartAskReader(
      PlainWeights.parse(bytes),
      hybrid: hybrid,
      simd: simd,
    );
    load.stop();

    final first = Stopwatch()..start();
    reader.run(inputs.first); // the first question also packs the lanes
    first.stop();
    final single = <double>[];
    for (var round = 0; round < rounds; round++) {
      for (final input in inputs) {
        final w = Stopwatch()..start();
        reader.run(input);
        single.add(w.elapsedMicroseconds / 1000);
      }
    }
    single.sort();
    final batch = Stopwatch()..start();
    for (final input in inputs) {
      reader.run(input);
    }
    batch.stop();
    String ms(double v) => v.toStringAsFixed(2);
    stdout.writeln(
      '${hybrid ? 'int8 (as TFLite)' : 'plain floats   '}'
      '${simd ? ', Float32x4' : ', doubles   '}: '
      'load ${ms(load.elapsedMicroseconds / 1000)} ms, '
      'first question ${ms(first.elapsedMicroseconds / 1000)} ms, '
      'per question median ${ms(single[single.length ~/ 2])} ms '
      '(p90 ${ms(single[single.length * 9 ~/ 10])} ms), '
      'batch of ${inputs.length} ${ms(batch.elapsedMicroseconds / 1000)} ms',
    );
  }
}
